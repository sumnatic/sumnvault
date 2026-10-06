# Cryptography Decisions

SumnVault uses standard constructions only. The planned v1 engine derives a 32-byte key from the user password with Argon2id and encrypts authenticated records with AES-256-GCM or ChaCha20-Poly1305, selected through a maintained cross-platform library after dependency review.

The password is never used directly as a key and is never persisted. A random per-vault salt is stored in the header. A fresh 12-byte nonce is generated for every record; sequence numbers are included as authenticated data so duplicate or reordered records fail validation. KDF parameters are stored in the header so the same vault can be opened on another supported platform.

Before release, parameters must be calibrated on representative desktop and Android hardware, with a documented minimum memory/time target and a weaker-device preset that still remains deliberately expensive. The implementation must include tests for wrong passwords, tampered headers, tampered ciphertext, nonce uniqueness, truncation, and interrupted commits.

This repository currently contains the format contract and UI shell. It intentionally does not claim that encrypted storage is production-ready until the reviewed crypto dependency, streaming engine, memory cleanup behavior, and corruption tests are implemented.
