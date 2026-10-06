# SumnVault Architecture

The product is split into a platform-independent vault engine and a Flutter presentation layer.

```text
Flutter UI -> application state -> domain services -> vault engine
                                              -> storage adapter
                                              -> crypto adapter
                                              -> compression adapter
```

The engine owns format parsing, virtual filesystem invariants, authenticated chunk records, atomic-save staging, verification, and session lock. Reopened vaults read only header and encrypted manifest during open; chunk ciphertext is indexed by disk position and fetched through `readFileStream` on demand. Imports are staged to a private temporary file and compressed before each chunk is encrypted. Save writes encrypted chunks to a separate staging file and then streams the replacement container sequentially, so the complete vault is not assembled in RAM. Full `verify` intentionally reads/authenticates every chunk. Flutter owns navigation, responsive layouts, progress presentation, and user-facing error translation. Platform adapters provide native file pickers, lifecycle events, drag and drop, and temporary-file policy.

Android is a first-class target: `AndroidStorage` uses a Kotlin `ContentResolver` bridge for `content://` documents, copying them to private cache for engine access and synchronizing after each save. Long operations stream chunks and run away from the UI isolate. A future version should retain persistable URI permissions and recover cache mappings across process death.

## Delivery order

1. Implement and test format, crypto, metadata, chunking, and atomic storage.
2. Add platform-neutral domain services and progress streams.
3. Connect responsive Flutter screens.
4. Add desktop adapters and Android document-provider integration.
5. Complete security review, accessibility, recovery tests, and performance profiling.
