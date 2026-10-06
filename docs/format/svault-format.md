# SumnVault Format v1

`.svault` is a portable, versioned container independent of Flutter, Dart, and the host filesystem.

## Layout

```text
Header (cleartext, fixed schema)
Encrypted metadata manifest (chunked)
Encrypted file chunks
Authenticated commit footer
```

The header starts with the ASCII magic `SVLT`, major version `1`, minor version, flags, a 16-byte random salt, KDF parameters, algorithm identifier, and a random 16-byte vault identifier. Unknown major versions and mandatory flags are rejected; readers never guess a format.

## Records and metadata

The encrypted manifest stores stable random item IDs, parent IDs, normalized names, item type, logical size, timestamps, compression method, chunk references, and schema version. File data is split into independently authenticated chunks with a default target of 4 MiB. The manifest and footer are encrypted/authenticated records, not plaintext indexes.

## Cryptography

The password is processed with Argon2id into a 256-bit key. Each record uses AEAD with a unique 96-bit nonce and associated data containing the vault ID, format version, record type, and sequence number. Nonces come from a cryptographically secure random source and are never reused with the same key. SumnVault must use a maintained, reviewed cryptography library and does not define new primitives.

## Atomic writes and recovery

Updates are written to a sibling temporary file, flushed and verified, then committed with an atomic replace where supported. The original remains untouched when writing or verification fails. Readers accept only a complete authenticated commit and ignore incomplete trailing data.

## Privacy boundaries

Names, folder structure, timestamps, logical sizes, and contents are encrypted. The operating system can still observe the `.svault` path, permissions, modification time, and approximate total size. Temporary exports, previews, thumbnails, backups, and swap files can expose plaintext and require explicit platform policy.

## Compatibility

Major versions are incompatible. Minor versions may add optional fields without changing v1 interpretation. Migrations create a new verified container and never rewrite the original silently.
