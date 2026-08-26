import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sumnvault/core/crypto/vault_crypto.dart';
import 'package:sumnvault/core/vault/vault_engine.dart';
import 'package:sumnvault/core/vault/vault_format.dart';

void main() {
  test('creates, saves, reopens, and authenticates a vault', () async {
    final file = File('${Directory.systemTemp.path}/sumnvault-test-${DateTime.now().microsecondsSinceEpoch}.svault');
    addTearDown(() async { if (await file.exists()) await file.delete(); });
    final engine = VaultEngine(crypto: VaultCrypto(kdf: const KdfParameters(memory: 1024, iterations: 1)));
    final session = await engine.create(file, 'vault password');
    session.addFolder('Documents');
    final folderId = session.entries.singleWhere((item) => item.name == 'Documents').id;
    session.addFile('note.txt', [1, 2, 3]);
    final noteId = session.entries.singleWhere((item) => item.name == 'note.txt').id;
    session.rename(noteId, 'renamed.txt');
    session.move(noteId, parentId: folderId);
    await session.verify();
    await session.save();

    final reopened = await engine.open(file, 'vault password');
    expect(reopened.entries.map((item) => item.name), containsAll(<String>['Documents', 'renamed.txt']));
    expect(reopened.entries.singleWhere((item) => item.name == 'renamed.txt').parentId, folderId);
    expect(await reopened.readFile(reopened.entries.singleWhere((item) => item.name == 'renamed.txt').id), [1, 2, 3]);
    reopened.rename(reopened.entries.singleWhere((item) => item.name == 'renamed.txt').id, 'saved-again.txt');
    await reopened.save();
    final savedAgain = await engine.open(file, 'vault password');
    expect(await savedAgain.readFile(savedAgain.entries.singleWhere((item) => item.name == 'saved-again.txt').id), [1, 2, 3]);
    await reopened.delete(folderId);
    expect(reopened.entries, isEmpty);
    reopened.addFile('temporary.txt', [4, 5]);
    reopened.lock();
    expect(reopened.isLocked, isTrue);
    expect(() => reopened.addFile('blocked.txt', [1]), throwsStateError);
    expect(() => reopened.readFile('missing'), throwsStateError);
    expect(engine.open(file, 'wrong password'), throwsA(anything));
  });

  test('round-trips data across chunk boundaries and rejects corruption', () async {
    final file = File('${Directory.systemTemp.path}/sumnvault-chunk-${DateTime.now().microsecondsSinceEpoch}.svault');
    addTearDown(() async { if (await file.exists()) await file.delete(); });
    final engine = VaultEngine(crypto: VaultCrypto(kdf: const KdfParameters(memory: 1024, iterations: 1)));
    final session = await engine.create(file, 'chunk password');
    final source = List<int>.generate(VaultFormat.defaultChunkSize + 17, (index) => index % 251);
    session.addFile('large.bin', source);
    await session.save();

    final reopened = await engine.open(file, 'chunk password');
    final streamed = <int>[];
    await for (final chunk in reopened.readFileStream(reopened.entries.single.id)) {
      streamed.addAll(chunk);
    }
    expect(streamed, source);
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await file.writeAsBytes(bytes);
    final corrupted = await engine.open(file, 'chunk password');
    expect(corrupted.verify(), throwsA(anything));
  });

  test('imports a stream through staging without a readAsBytes path', () async {
    final file = File('${Directory.systemTemp.path}/sumnvault-stream-${DateTime.now().microsecondsSinceEpoch}.svault');
    addTearDown(() async { if (await file.exists()) await file.delete(); });
    final engine = VaultEngine(crypto: VaultCrypto(kdf: const KdfParameters(memory: 1024, iterations: 1)));
    final session = await engine.create(file, 'stream password');
    await session.addFileStream('stream.bin', Stream<List<int>>.fromIterable([List<int>.filled(32, 1), List<int>.filled(32, 2)]));
    await session.save();
    final reopened = await engine.open(file, 'stream password');
    expect((await reopened.readFile(reopened.entries.single.id)).length, 64);
  });
}
