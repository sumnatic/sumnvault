# SumnVault Threat Model

## Assets

Vault contents, names, folder structure, timestamps, and the password-derived key are sensitive. A locked `.svault` must be confidential and tamper-evident.

## Adversaries and guarantees

An attacker with a copied vault can perform offline password guesses; resistance depends on password entropy and calibrated Argon2id parameters. Modified, truncated, or corrupted bytes must fail AEAD or commit verification and must never be returned as valid content.

## Out of scope

A compromised device, malicious process while unlocked, keyloggers, screen capture, and plaintext deliberately exported to another application are outside the protection boundary. There is no recovery password, backdoor, or universal Sumnatic key.

## Controls

Keys are held only for the unlocked session and cleared where the runtime permits. Passwords, keys, file content, and unnecessary metadata are never logged. Import and export reject traversal, absolute paths, symlinks, invalid names, decompression bombs, integer overflow, and resource exhaustion. Long operations stream chunks away from the UI isolate.

Android lifecycle transitions must lock or clear sensitive state according to the selected policy. Preview and export caches must be private, temporary where possible, and removed on lock.

The session lock clears plaintext buffers, virtual filesystem indexes, and encrypted chunk references, then rejects further operations. Dart does not provide guaranteed compiler/runtime control over every copy of a `SecretKey`, so key zeroization is best effort rather than an absolute guarantee; a compromised process remains outside the model.
