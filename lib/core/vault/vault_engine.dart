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
      final headerBytes = await access.read(headerLength);
      if (headerBytes.length != headerLength) throw const FormatException('Corrupt vault header');
      final header = jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
      final manifestLengthBytes = await access.read(4);
      if (manifestLengthBytes.length != 4) throw const FormatException('Corrupt vault manifest');
      final manifestLength = _readUint32(manifestLengthBytes, 0);
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
    items[id] = VaultItem(id: item.id, parentId: parentId, name: item.name, isDirectory: item.isDirectory, logicalSize: item.logicalSize);
  }

  void delete(String id) {
    _ensureUnlocked();
    final item = items.remove(id);
    if (item == null) throw StateError('Item not found');
    final children = items.values.where((entry) => entry.parentId == id).map((entry) => entry.id).toList();
    for (final child in children) {
      delete(child);
    }
    contents.remove(id);
    encryptedChunks.remove(id);
  }

  Future<void> verify() async {
    _ensureUnlocked();
    for (final item in items.values) {
      validateVaultName(item.name);
      if (item.parentId != null && !items.containsKey(item.parentId)) throw const FormatException('Missing parent reference');
      if (!item.isDirectory && (await readFile(item.id)).length != item.logicalSize) throw const FormatException('File size mismatch');
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
          yield await crypto.decrypt(payload, key, associatedData: [...vaultId, ...utf8.encode(id), reference.sequence]);
        }
      } finally {
        await access.close();
      }
      return;
    }
    final memoryChunks = chunks!;
    for (var sequence = 0; sequence < memoryChunks.length; sequence++) {
      yield await crypto.decrypt(memoryChunks[sequence], key, associatedData: [...vaultId, ...utf8.encode(id), sequence]);
    }
  }

  Future<void> save() async {
    _ensureUnlocked();
    final fileRecords = <String, List<Map<String, String>>>{};
    for (final item in items.values.where((item) => !item.isDirectory)) {
      final data = await _materialize(item.id);
      final records = <Map<String, String>>[];
      for (var offset = 0, sequence = 0; offset < data.length; offset += VaultFormat.defaultChunkSize, sequence++) {
        final end = min(offset + VaultFormat.defaultChunkSize, data.length);
        final encrypted = await crypto.encrypt(data.sublist(offset, end), key, associatedData: [...vaultId, ...utf8.encode(item.id), sequence]);
        records.add({'nonce': base64Encode(encrypted.nonce), 'mac': base64Encode(encrypted.mac), 'cipher': base64Encode(encrypted.cipherText)});
      }
      fileRecords[item.id] = records;
      encryptedChunks[item.id] = records.map((record) => EncryptedPayload(nonce: Uint8List.fromList(base64Decode(record['nonce']!)), mac: Uint8List.fromList(base64Decode(record['mac']!)), cipherText: Uint8List.fromList(base64Decode(record['cipher']!)))).toList();
    }
    chunkReferences.clear();
    final manifest = jsonEncode({
      'items': items.values.map((item) => {'id': item.id, 'parentId': item.parentId, 'name': item.name, 'directory': item.isDirectory, 'size': item.logicalSize}).toList(),
      'chunks': fileRecords.map((id, records) => MapEntry(id, records.length)),
    });
    final header = utf8.encode(jsonEncode({'version': 1, 'salt': base64Encode(salt), 'id': base64Encode(vaultId), 'kdf': {'memory': crypto.kdf.memory, 'iterations': crypto.kdf.iterations, 'parallelism': crypto.kdf.parallelism}}));
    final aad = [...vaultId, 1, 0];
    final encrypted = await crypto.encrypt(utf8.encode(manifest), key, associatedData: aad);
    final payload = utf8.encode(jsonEncode({'nonce': base64Encode(encrypted.nonce), 'mac': base64Encode(encrypted.mac), 'cipher': base64Encode(encrypted.cipherText)}));
    final output = BytesBuilder()..add(VaultFormat.magic)..addByte(1)..add(_uint32(header.length))..add(header)..add(_uint32(payload.length))..add(payload);
    for (final item in items.values.where((item) => !item.isDirectory)) {
      for (final record in fileRecords[item.id]!) {
        final encrypted = [...base64Decode(record['nonce']!), ...base64Decode(record['mac']!), ...base64Decode(record['cipher']!)];
        output.add(_uint32(encrypted.length));
        output.add(encrypted);
      }
    }
    final temporary = File('${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temporary.writeAsBytes(output.takeBytes(), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
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
      chunkReferences[entry.key] = List.generate(entry.value as int, (sequence) => ChunkReference(sequence: sequence));
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
        if (length < 28) throw const FormatException('Invalid chunk record');
        final payloadPosition = position + 4;
        final authentication = await access.read(28);
        if (authentication.length != 28) throw const FormatException('Truncated chunk record');
        reference.position = payloadPosition;
        reference.length = length;
        position += 4 + length;
      }
    }
  }

  Future<Uint8List> _materialize(String id) async {
    final current = contents[id];
    if (current != null) return current;
    return readFile(id);
  }

  void lock() {
    if (_locked) return;
    for (final data in contents.values) {
      data.fillRange(0, data.length, 0);
    }
    contents.clear();
    encryptedChunks.clear();
    items.clear();
    _locked = true;
  }

  void _ensureUnlocked() {
    if (_locked) throw StateError('Vault is locked');
  }

  String _id() => base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
  List<int> _uint32(int value) => [value >> 24 & 255, value >> 16 & 255, value >> 8 & 255, value & 255];
}
