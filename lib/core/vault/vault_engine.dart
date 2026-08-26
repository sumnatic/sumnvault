import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sumnvault/core/crypto/vault_crypto.dart';
import 'package:sumnvault/core/vault/chunk_reference.dart';
import 'package:sumnvault/core/vault/vault_format.dart';

int _readUint32(List<int> bytes, int offset) => ByteData.sublistView(Uint8List.fromList(bytes), offset, offset + 4).getUint32(0, Endian.big);

class VaultEngine {
  VaultEngine({VaultCrypto? crypto}) : crypto = crypto ?? VaultCrypto();
  final VaultCrypto crypto;

  Future<VaultSession> create(File file, String password) async {
    final salt = _randomBytes(VaultFormat.saltLength);
    final id = _randomBytes(16);
    final key = await crypto.deriveKey(password, salt);
    final session = VaultSession._(file: file, key: key, salt: salt, vaultId: id, crypto: crypto);
    await session.save();
    return session;
  }

  Future<VaultSession> open(File file, String password) async {
    final access = await file.open();
    try {
      final prefix = await access.read(9);
      if (prefix.length < 9 || !_hasMagic(prefix)) throw const FormatException('Unsupported vault format');
      final headerLength = _readUint32(prefix, 5);
      if (headerLength == 0 || headerLength > VaultFormat.maxHeaderLength) throw const FormatException('Invalid vault header length');
      final headerBytes = await access.read(headerLength);
      if (headerBytes.length != headerLength) throw const FormatException('Corrupt vault header');
      final header = jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
      final manifestLengthBytes = await access.read(4);
      if (manifestLengthBytes.length != 4) throw const FormatException('Corrupt vault manifest');
      final manifestLength = _readUint32(manifestLengthBytes, 0);
      if (manifestLength == 0 || manifestLength > VaultFormat.maxManifestLength) throw const FormatException('Invalid vault manifest length');
      final manifestBytes = await access.read(manifestLength);
      if (manifestBytes.length != manifestLength) throw const FormatException('Corrupt vault manifest');
      final salt = base64Decode(header['salt'] as String);
      final id = base64Decode(header['id'] as String);
      final storedKdf = (header['kdf'] as Map<String, dynamic>?) ?? const {};
      final configuredCrypto = VaultCrypto(kdf: KdfParameters(
        memory: storedKdf['memory'] as int? ?? crypto.kdf.memory,
        iterations: storedKdf['iterations'] as int? ?? crypto.kdf.iterations,
        parallelism: storedKdf['parallelism'] as int? ?? crypto.kdf.parallelism,
      ));
      if (configuredCrypto.kdf.memory > VaultFormat.maxKdfMemory || configuredCrypto.kdf.iterations > VaultFormat.maxKdfIterations || configuredCrypto.kdf.parallelism > VaultFormat.maxKdfParallelism) throw const FormatException('Vault KDF parameters exceed local policy');
      final key = await configuredCrypto.deriveKey(password, salt);
      final session = VaultSession._(file: file, key: key, salt: salt, vaultId: id, crypto: configuredCrypto);
      await session._readManifest(manifestBytes);
      await session._scanChunkRecords(access, 9 + headerLength + 4 + manifestLength);
      return session;
    } finally {
      await access.close();
    }
  }

  bool _hasMagic(List<int> bytes) => List<int>.generate(4, (index) => bytes[index]).toString() == VaultFormat.magic.toString();

  int _readUint32(List<int> bytes, int offset) => ByteData.sublistView(Uint8List.fromList(bytes), offset, offset + 4).getUint32(0, Endian.big);

  Uint8List _randomBytes(int length) => Uint8List.fromList(List<int>.generate(length, (_) => Random.secure().nextInt(256)));
}

class VaultSession {
  VaultSession._({required this.file, required this.key, required this.salt, required this.vaultId, required this.crypto});
  final File file;
  final SecretKey key;
  final List<int> salt;
  final List<int> vaultId;
  final VaultCrypto crypto;
  final Map<String, VaultItem> items = {};
  final Map<String, Uint8List> contents = {};
  final Map<String, List<EncryptedPayload>> encryptedChunks = {};
  final Map<String, List<ChunkReference>> chunkReferences = {};
  final Map<String, File> pendingSources = {};
  final Set<String> compressedItems = {};
  bool _locked = false;

  bool get isLocked => _locked;

  List<VaultItem> get entries => items.values.toList(growable: false);

  void addFolder(String name, {String? parentId}) {
    _ensureUnlocked();
    validateVaultName(name);
    final id = _id();
    items[id] = VaultItem(id: id, parentId: parentId, name: name, isDirectory: true, logicalSize: 0);
  }

  void addFile(String name, List<int> data, {String? parentId}) {
    _ensureUnlocked();
    validateVaultName(name);
    final id = _id();
    final bytes = Uint8List.fromList(data);
    items[id] = VaultItem(id: id, parentId: parentId, name: name, isDirectory: false, logicalSize: bytes.length);
    contents[id] = bytes;
  }

  Future<void> addFileStream(String name, Stream<List<int>> source, {String? parentId}) async {
    _ensureUnlocked();
    validateVaultName(name);
    final staging = File('${file.path}.import-${Random.secure().nextInt(1 << 31)}');
    if (await staging.exists()) throw StateError('Temporary import collision');
    var size = 0;
    final sink = staging.openWrite();
    try {
      await for (final chunk in source) {
        sink.add(chunk);
        size += chunk.length;
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await staging.exists()) await staging.delete();
      rethrow;
    }
    final id = _id();
    items[id] = VaultItem(id: id, parentId: parentId, name: name, isDirectory: false, logicalSize: size);
    pendingSources[id] = staging;
  }

  Future<File> createSnapshot(File destination) async {
    _ensureUnlocked();
    await save();
    return file.copy(destination.path);
  }

  Future<VaultSession> restoreSnapshot(File snapshot, String password) async {
    _ensureUnlocked();
    final candidate = await VaultEngine(crypto: crypto).open(snapshot, password);
    await candidate.verify();
    final temporary = File('${file.path}.restore-${Random.secure().nextInt(1 << 31)}');
    final sink = temporary.openWrite();
    try {
      await sink.addStream(snapshot.openRead());
      await sink.close();
      final backup = File('${file.path}.previous-${Random.secure().nextInt(1 << 31)}');
      if (await file.exists()) await file.rename(backup.path);
      try {
        await temporary.rename(file.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (await file.exists()) await file.delete();
        if (await backup.exists()) await backup.rename(file.path);
        rethrow;
      }
    } catch (_) {
      await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    lock();
    return VaultEngine(crypto: crypto).open(file, password);
  }

  Future<List<File>> listSnapshots() async {
    final directory = file.parent;
    final baseName = file.path.split(Platform.pathSeparator).last;
    final prefix = '$baseName.snapshot-';
    final snapshots = await directory.list().where((entry) => entry is File && entry.path.split(Platform.pathSeparator).last.startsWith(prefix)).map((entry) => entry as File).toList();
    snapshots.sort((a, b) => b.path.compareTo(a.path));
    return snapshots;
  }

  void rename(String id, String name) {
    _ensureUnlocked();
    validateVaultName(name);
    final item = items[id];
    if (item == null) throw StateError('Item not found');
    items[id] = VaultItem(id: item.id, parentId: item.parentId, name: name, isDirectory: item.isDirectory, logicalSize: item.logicalSize);
  }

  void move(String id, {String? parentId}) {
    _ensureUnlocked();
    final item = items[id];
    if (item == null) throw StateError('Item not found');
    if (parentId != null && (!items.containsKey(parentId) || !items[parentId]!.isDirectory)) throw StateError('Destination folder not found');
    if (parentId == id) throw StateError('An item cannot contain itself');
    final visited = <String>{};
    var ancestor = parentId;
    while (ancestor != null) {
      if (!visited.add(ancestor) || ancestor == id) throw StateError('A folder cannot be moved inside its descendant');
      ancestor = items[ancestor]?.parentId;
    }
    items[id] = VaultItem(id: item.id, parentId: parentId, name: item.name, isDirectory: item.isDirectory, logicalSize: item.logicalSize);
  }

  Future<void> delete(String id) async {
    _ensureUnlocked();
    final item = items.remove(id);
    if (item == null) throw StateError('Item not found');
    final children = items.values.where((entry) => entry.parentId == id).map((entry) => entry.id).toList();
    for (final child in children) {
      await delete(child);
    }
    contents.remove(id);
    encryptedChunks.remove(id);
    final pending = pendingSources.remove(id);
    if (pending != null && await pending.exists()) await pending.delete();
  }

  Future<void> verify() async {
    _ensureUnlocked();
    for (final item in items.values) {
      validateVaultName(item.name);
      if (item.parentId != null && !items.containsKey(item.parentId)) throw const FormatException('Missing parent reference');
      if (!item.isDirectory && (await readFile(item.id)).length != item.logicalSize) throw const FormatException('File size mismatch');
    }
    for (final item in items.values) {
      final visited = <String>{};
      var ancestor = item.parentId;
      while (ancestor != null) {
        if (!visited.add(ancestor)) throw const FormatException('Folder hierarchy contains a cycle');
        ancestor = items[ancestor]?.parentId;
      }
    }
  }

  Future<Uint8List> readFile(String id) async {
    _ensureUnlocked();
    final output = BytesBuilder();
    await for (final chunk in readFileStream(id)) {
      output.add(chunk);
    }
    return output.takeBytes();
  }

  Stream<Uint8List> readFileStream(String id) async* {
    _ensureUnlocked();
    if (!items.containsKey(id) || items[id]!.isDirectory) throw StateError('File is not available');
    final inMemory = contents[id];
    if (inMemory != null) {
      yield Uint8List.fromList(inMemory);
      return;
    }
    final chunks = encryptedChunks[id];
    final references = chunkReferences[id];
    if (chunks == null && references == null) throw StateError('File is not available');
    if (references != null) {
      final access = await file.open();
      try {
        for (final reference in references) {
          await access.setPosition(reference.position);
          final record = await access.read(reference.length);
          final payload = EncryptedPayload(nonce: Uint8List.fromList(record.sublist(0, 12)), mac: Uint8List.fromList(record.sublist(12, 28)), cipherText: Uint8List.fromList(record.sublist(28)));
          final clear = await crypto.decrypt(payload, key, associatedData: [...vaultId, ...utf8.encode(id), reference.sequence]);
          yield compressedItems.contains(id) ? Uint8List.fromList(ZLibCodec().decode(clear)) : clear;
        }
      } finally {
        await access.close();
      }
      return;
    }
    final memoryChunks = chunks!;
    for (var sequence = 0; sequence < memoryChunks.length; sequence++) {
      final clear = await crypto.decrypt(memoryChunks[sequence], key, associatedData: [...vaultId, ...utf8.encode(id), sequence]);
      yield compressedItems.contains(id) ? Uint8List.fromList(ZLibCodec().decode(clear)) : clear;
    }
  }

  Future<void> save() async {
    _ensureUnlocked();
    final counts = <String, int>{};
    final dataStaging = File('${file.path}.data-${Random.secure().nextInt(1 << 31)}');
    if (await dataStaging.exists()) throw StateError('Temporary data collision');
    final dataSink = dataStaging.openWrite();
    try {
      for (final item in items.values.where((item) => !item.isDirectory)) {
        final count = pendingSources[item.id] != null
            ? await _writeEncryptedSource(pendingSources[item.id]!, item.id, dataSink)
            : await _writeEncryptedStream(readFileStream(item.id), item.id, dataSink);
        counts[item.id] = count;
        compressedItems.add(item.id);
      }
      await dataSink.close();
    } catch (_) {
      await dataSink.close();
      if (await dataStaging.exists()) await dataStaging.delete();
      rethrow;
    }
    for (final source in pendingSources.values) {
      if (await source.exists()) await source.delete();
    }
    pendingSources.clear();
    chunkReferences.clear();
    final manifest = jsonEncode({
      'items': items.values.map((item) => {'id': item.id, 'parentId': item.parentId, 'name': item.name, 'directory': item.isDirectory, 'size': item.logicalSize}).toList(),
      'chunks': counts.map((id, count) => MapEntry(id, {'count': count, 'compression': 'zlib'})),
    });
    final header = utf8.encode(jsonEncode({'version': 1, 'salt': base64Encode(salt), 'id': base64Encode(vaultId), 'kdf': {'memory': crypto.kdf.memory, 'iterations': crypto.kdf.iterations, 'parallelism': crypto.kdf.parallelism}}));
    final aad = [...vaultId, 1, 0];
    final encrypted = await crypto.encrypt(utf8.encode(manifest), key, associatedData: aad);
    final payload = utf8.encode(jsonEncode({'nonce': base64Encode(encrypted.nonce), 'mac': base64Encode(encrypted.mac), 'cipher': base64Encode(encrypted.cipherText)}));
    final temporary = File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    final output = temporary.openWrite();
    output.add(VaultFormat.magic);
    output.add([1]);
    output.add(_uint32(header.length));
    output.add(header);
    output.add(_uint32(payload.length));
    output.add(payload);
    await output.addStream(dataStaging.openRead());
    await output.close();
    if (await dataStaging.exists()) await dataStaging.delete();
    final backup = File('${file.path}.previous-${Random.secure().nextInt(1 << 31)}');
    final hadOriginal = await file.exists();
    if (hadOriginal) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
    final access = await file.open();
    try {
      await _scanChunkRecords(access, 9 + header.length + 4 + payload.length);
    } finally {
      await access.close();
    }
  }

  Future<void> _readManifest(List<int> bytes) async {
    final record = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final encrypted = EncryptedPayload(nonce: Uint8List.fromList(base64Decode(record['nonce'] as String)), mac: Uint8List.fromList(base64Decode(record['mac'] as String)), cipherText: Uint8List.fromList(base64Decode(record['cipher'] as String)));
    final clear = await crypto.decrypt(encrypted, key, associatedData: [...vaultId, 1, 0]);
    final manifest = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    for (final raw in manifest['items'] as List<dynamic>) {
      final item = raw as Map<String, dynamic>;
      final entry = VaultItem(id: item['id'] as String, parentId: item['parentId'] as String?, name: item['name'] as String, isDirectory: item['directory'] as bool, logicalSize: item['size'] as int);
      validateVaultName(entry.name);
      items[entry.id] = entry;
    }
    final chunks = manifest['chunks'] as Map<String, dynamic>? ?? const {};
    for (final entry in chunks.entries) {
      final descriptor = entry.value is int ? {'count': entry.value} : entry.value as Map<String, dynamic>;
      chunkReferences[entry.key] = List.generate(descriptor['count'] as int, (sequence) => ChunkReference(sequence: sequence));
      if (descriptor['compression'] == 'zlib') compressedItems.add(entry.key);
    }
  }

  Future<void> _scanChunkRecords(RandomAccessFile access, int position) async {
    for (final item in items.values.where((item) => !item.isDirectory)) {
      final references = chunkReferences[item.id] ?? const <ChunkReference>[];
      for (final reference in references) {
        await access.setPosition(position);
        final lengthBytes = await access.read(4);
        if (lengthBytes.length != 4) throw const FormatException('Truncated chunk record');
        final length = _readUint32(lengthBytes, 0);
        if (length < 28 || length > VaultFormat.maxChunkRecordLength) throw const FormatException('Invalid chunk record');
        final payloadPosition = position + 4;
        final authentication = await access.read(28);
        if (authentication.length != 28) throw const FormatException('Truncated chunk record');
        reference.position = payloadPosition;
        reference.length = length;
        position += 4 + length;
      }
    }
  }

  Future<int> _writeEncryptedStream(Stream<Uint8List> source, String id, IOSink sink) async {
    var count = 0;
    await for (final chunk in source) {
      await _writeEncryptedChunk(chunk, id, count++, sink);
    }
    return count;
  }

  Future<int> _writeEncryptedSource(File source, String id, IOSink sink) async {
    final buffer = <int>[];
    var sequence = 0;
    await for (final incoming in source.openRead()) {
      buffer.addAll(incoming);
      while (buffer.length >= VaultFormat.defaultChunkSize) {
        await _writeEncryptedChunk(Uint8List.fromList(buffer.sublist(0, VaultFormat.defaultChunkSize)), id, sequence++, sink);
        buffer.removeRange(0, VaultFormat.defaultChunkSize);
      }
    }
    if (buffer.isNotEmpty) await _writeEncryptedChunk(Uint8List.fromList(buffer), id, sequence++, sink);
    return sequence;
  }

  Future<void> _writeEncryptedChunk(List<int> clear, String id, int sequence, IOSink sink) async {
    final compressed = ZLibCodec().encode(clear);
    final encrypted = await crypto.encrypt(compressed, key, associatedData: [...vaultId, ...utf8.encode(id), sequence]);
    final List<int> payload = [...encrypted.nonce, ...encrypted.mac, ...encrypted.cipherText];
    sink.add(_uint32(payload.length));
    sink.add(payload);
  }

  void lock() {
    if (_locked) return;
    for (final data in contents.values) {
      data.fillRange(0, data.length, 0);
    }
    contents.clear();
    encryptedChunks.clear();
    compressedItems.clear();
    pendingSources.clear();
    items.clear();
    _locked = true;
  }

  void _ensureUnlocked() {
    if (_locked) throw StateError('Vault is locked');
  }

  String _id() => base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
  List<int> _uint32(int value) => [value >> 24 & 255, value >> 16 & 255, value >> 8 & 255, value & 255];
}
