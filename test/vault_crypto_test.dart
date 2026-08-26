import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sumnvault/core/crypto/vault_crypto.dart';

void main() {
  test('encrypts and decrypts with Argon2id and AES-GCM', () async {
    final crypto = VaultCrypto(kdf: const KdfParameters(memory: 1024, iterations: 1));
    final key = await crypto.deriveKey('correct horse battery staple', List<int>.filled(16, 7));
    final encrypted = await crypto.encrypt(Uint8List.fromList([1, 2, 3]), key, associatedData: [1, 2]);

    expect(await crypto.decrypt(encrypted, key, associatedData: [1, 2]), [1, 2, 3]);
  });

  test('rejects wrong password and tampered ciphertext', () async {
    final crypto = VaultCrypto(kdf: const KdfParameters(memory: 1024, iterations: 1));
    final salt = List<int>.filled(16, 8);
    final key = await crypto.deriveKey('right password', salt);
    final encrypted = await crypto.encrypt([9, 8, 7], key, associatedData: [4]);
    final wrongKey = await crypto.deriveKey('wrong password', salt);

    expect(() => crypto.decrypt(encrypted, wrongKey, associatedData: [4]), throwsA(anything));
    final tampered = EncryptedPayload(nonce: encrypted.nonce, mac: encrypted.mac, cipherText: Uint8List.fromList([...encrypted.cipherText]..[0] ^= 1));
    expect(() => crypto.decrypt(tampered, key, associatedData: [4]), throwsA(anything));
  });
}
