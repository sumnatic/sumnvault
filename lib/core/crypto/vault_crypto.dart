import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class KdfParameters {
  const KdfParameters({this.parallelism = 1, this.memory = 19 * 1024, this.iterations = 2, this.hashLength = 32});

  final int parallelism;
  final int memory;
  final int iterations;
  final int hashLength;

  Argon2id get algorithm => Argon2id(parallelism: parallelism, memory: memory, iterations: iterations, hashLength: hashLength);
}

class EncryptedPayload {
  const EncryptedPayload({required this.nonce, required this.mac, required this.cipherText});

  final Uint8List nonce;
  final Uint8List mac;
  final Uint8List cipherText;
}

class VaultCrypto {
  VaultCrypto({this.kdf = const KdfParameters()}) : _cipher = AesGcm.with256bits();

  final KdfParameters kdf;
  final AesGcm _cipher;

  Future<SecretKey> deriveKey(String password, List<int> salt) => kdf.algorithm.deriveKey(secretKey: SecretKey(password.codeUnits), nonce: salt);

  Future<EncryptedPayload> encrypt(List<int> clearText, SecretKey key, {required List<int> associatedData}) async {
    final box = await _cipher.encrypt(clearText, secretKey: key, aad: associatedData);
    return EncryptedPayload(nonce: Uint8List.fromList(box.nonce), mac: Uint8List.fromList(box.mac.bytes), cipherText: Uint8List.fromList(box.cipherText));
  }

  Future<Uint8List> decrypt(EncryptedPayload payload, SecretKey key, {required List<int> associatedData}) async {
    final box = SecretBox(payload.cipherText, nonce: payload.nonce, mac: Mac(payload.mac));
    final clearText = await _cipher.decrypt(box, secretKey: key, aad: associatedData);
    return Uint8List.fromList(clearText);
  }
}
