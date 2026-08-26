import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sumnvault/core/vault/vault_format.dart';

void main() {
  test('v1 header accepts the documented salt and vault id sizes', () {
    final header = VaultHeader(
      minorVersion: 0,
      flags: 0,
      salt: Uint8List(VaultFormat.saltLength),
      vaultId: Uint8List(16),
    );

    expect(header.isV1, isTrue);
    expect(VaultFormat.magic, [0x53, 0x56, 0x4c, 0x54]);
  });

  test('internal names reject traversal and path separators', () {
    expect(validateVaultName('document.pdf'), 'document.pdf');
    expect(() => validateVaultName('../secret'), throwsFormatException);
    expect(() => validateVaultName(r'folder\file'), throwsFormatException);
    expect(() => validateVaultName(''), throwsFormatException);
  });
}
