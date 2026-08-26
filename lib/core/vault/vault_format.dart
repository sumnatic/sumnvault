import 'dart:typed_data';

/// Stable identifiers and limits for SumnVault container format v1.
abstract final class VaultFormat {
  static const magic = [0x53, 0x56, 0x4c, 0x54];
  static const majorVersion = 1;
  static const defaultChunkSize = 4 * 1024 * 1024;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const keyLength = 32;
  static const maxHeaderLength = 64 * 1024;
  static const maxManifestLength = 64 * 1024 * 1024;
  static const maxChunkRecordLength = defaultChunkSize + 64 * 1024;
  static const maxKdfMemory = 1024 * 1024;
  static const maxKdfIterations = 12;
  static const maxKdfParallelism = 8;
}

class VaultHeader {
  const VaultHeader({required this.minorVersion, required this.flags, required this.salt, required this.vaultId});

  final int minorVersion;
  final int flags;
  final Uint8List salt;
  final Uint8List vaultId;

  bool get isV1 => minorVersion >= 0 && salt.length == VaultFormat.saltLength && vaultId.length == 16;
}

class VaultItem {
  const VaultItem({required this.id, required this.parentId, required this.name, required this.isDirectory, required this.logicalSize});

  final String id;
  final String? parentId;
  final String name;
  final bool isDirectory;
  final int logicalSize;
}

/// Rejects names that could escape the virtual filesystem during export.
String validateVaultName(String name) {
  if (name.isEmpty || name == '.' || name == '..' || name.contains('/') || name.contains('\\') || name.contains('\u0000')) {
    throw FormatException('Invalid vault item name');
  }
  return name;
}
