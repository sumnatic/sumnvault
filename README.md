# SumnVault 🔐

**Your files. One vault. Fully private.**

SumnVault is a modern, cross-platform application for storing sensitive files inside secure, portable and encrypted digital vaults.

Built by **Sumnatic**, SumnVault is designed around a simple idea:

> Your sensitive files should belong to you — not to a cloud service.

A `.svault` file can contain documents, certificates, images, backups and other files inside a virtual filesystem protected by a password.

---

## ✨ Features

### 🔐 Secure Vaults

Create a `.svault` file protected by a user-defined password.

Each vault is designed to provide:

* Strong password-based key derivation
* Authenticated encryption
* Encrypted filesystem metadata
* Protection against unauthorized modifications
* Portable, self-contained storage
* Offline-first operation

SumnVault does **not** require an online account to create or use a vault.

---

### 📁 Virtual Filesystem

A vault behaves like its own filesystem.

```text
Personal.svault
│
├── Documents/
│   ├── Identity/
│   │   ├── RG.pdf
│   │   └── CPF.pdf
│   │
│   └── Certificates/
│       ├── Certificate-01.pdf
│       └── Certificate-02.pdf
│
├── Photos/
│   ├── Photo-01.jpg
│   └── Photo-02.png
│
└── Important/
    └── Backup.txt
```

Inside SumnVault, users can:

* Create folders
* Add files
* Rename files
* Move files
* Replace files
* Delete files
* Rename folders
* Move folders
* Search files
* Export files

All of this happens without exposing the vault's internal contents as ordinary plaintext files.

---

### 📦 Portable `.svault` Format

A SumnVault is represented by a single:

```text
.svault
```

file.

This makes vaults easy to:

* Back up
* Copy between computers
* Store on external drives
* Transfer between supported devices
* Keep alongside other backups
* Store using third-party cloud storage

The vault format is designed to be independent of the user interface and operating system.

---

### 🗜️ Compression

SumnVault can compress data before encryption when doing so provides a meaningful size reduction.

The general pipeline is:

```text
File
  ↓
Compression
  ↓
Encryption
  ↓
.svault
```

Already-compressed formats can be stored without unnecessary compression.

---

### 🧩 Chunk-Based Storage

Vault data is designed around encrypted chunks rather than requiring entire files or entire vaults to be loaded into memory.

This allows SumnVault to scale toward:

* Large files
* Large vaults
* Partial reads
* Streaming operations
* Incremental modifications

The goal is to make a vault containing hundreds of gigabytes fundamentally different from simply loading hundreds of gigabytes into RAM.

---

### 🔒 Vault Lock

Vaults can be manually or automatically locked.

When locked, the application stops exposing the vault's contents and requires authentication to access it again.

Planned lock triggers include:

* Manual lock
* Inactivity timeout
* Application exit
* System lock/suspend where supported
* Mobile application lifecycle events

---

### 🔍 Search

Search files and folders directly inside the vault.

Initial search focuses on:

* File names
* Folder names
* Paths

SumnVault is designed to avoid creating unnecessary plaintext indexes outside the encrypted vault.

---

### 👁️ Secure Preview

SumnVault can preview supported file types without requiring the user to permanently extract them to the operating system filesystem.

Planned/common preview formats include:

* PDF
* JPEG
* PNG
* WebP
* TXT
* JSON

Preview architecture is designed to minimize unnecessary plaintext temporary files.

---

### 💻 Cross-Platform

SumnVault is built with **Flutter and Dart** and targets:

* 🪟 Windows
* 🐧 Linux
* 🍎 macOS
* 📱 Android

The same `.svault` should be usable across supported platforms.

For example:

```text
Windows
   │
   ▼
Personal.svault
   │
   ▼
Android
   │
   ▼
macOS
   │
   ▼
Linux
```

---

## 🛡️ Security

Security is the highest priority of SumnVault.

SumnVault does **not** implement custom cryptographic algorithms.

Instead, it is designed to use established cryptographic primitives and mature implementations.

The conceptual encryption flow is:

```text
User Password
      │
      ▼
Password KDF
      │
      ▼
Encryption Key
      │
      ▼
Authenticated Encryption
      │
      ▼
Encrypted Vault
```

The architecture is designed around technologies such as:

* Argon2id for password-based key derivation
* AES-256-GCM and/or ChaCha20-Poly1305 for authenticated encryption
* Cryptographically secure random salts and nonces

The final algorithms and parameters should be selected and documented based on the specific implementation and security review.

### Important

SumnVault cannot protect data from a fully compromised device while a vault is unlocked.

If malware has control over a computer or phone, it may potentially access information that the user is actively viewing or editing.

SumnVault aims to protect the vault itself against unauthorized access, theft of the `.svault` file, and unauthorized modification.

---

## 🧱 Architecture

SumnVault is designed with a strong separation between the application interface and the vault engine.

Conceptually:

```text
                 SumnVault
                     │
        ┌────────────┴────────────┐
        │                         │
    Flutter UI                Core Engine
        │                         │
        │          ┌──────────────┼──────────────┐
        │          │              │              │
        │        Vault          Crypto        Storage
        │          │              │              │
        │       Metadata       KDF/AEAD       Chunks
        │          │              │              │
        │       Filesystem     Security      Compression
        │
        └──── Platform Integration
                 │
       ┌─────────┼─────────┐
       │         │         │
    Windows    Linux     macOS
                          │
                        Android
```

The core should remain independent from Flutter's presentation layer wherever practical.

This allows the vault engine to potentially be reused in the future by:

* CLI tools
* Other interfaces
* Libraries
* Automation
* Additional platforms

---

## 📱 Android

Android is treated as a first-class platform.

SumnVault should integrate with modern Android storage APIs rather than assuming unrestricted filesystem access.

This includes support for workflows such as:

* Opening existing `.svault` files
* Creating vaults
* Importing files
* Exporting files
* Choosing storage locations
* Working with external storage when permitted
* Handling application backgrounding and lifecycle events

Large file operations should use streaming rather than loading entire files into memory.

---

## 🖥️ Desktop

On Windows, Linux and macOS, SumnVault provides a desktop-oriented experience with:

* Resizable windows
* Keyboard shortcuts
* Drag-and-drop
* Context menus
* Multi-selection
* File pickers
* Keyboard navigation
* Native filesystem integration

---

## 💾 Data Integrity

A corrupted or interrupted save operation should not silently destroy the user's vault.

SumnVault is designed around safe-write principles such as:

```text
Original.svault
      │
      ▼
Temporary.svault
      │
      ▼
Write + Verify
      │
      ▼
Atomic Commit
      │
      ▼
Original.svault
```

The goal is to ensure that an interrupted operation leaves the previous valid vault intact whenever technically possible.

A future **Verify Vault** feature will allow users to check:

* Metadata integrity
* Chunk integrity
* Authentication
* Filesystem consistency
* Corrupted blocks

---

## 🔑 Password Recovery

SumnVault does not contain a secret master password or universal backdoor.

If a user loses the password to a vault, SumnVault should not be able to simply bypass its encryption.

Optional recovery mechanisms may be introduced in the future, but they must be explicitly configured by the user and designed as cryptographic recovery mechanisms rather than hidden backdoors.

---

## ☁️ Cloud Philosophy

Cloud synchronization is **not required** to use SumnVault.

The fundamental product is local and offline.

---

## 🎨 Design Philosophy

SumnVault should feel like **premium privacy software**.

The design should be:

* Minimal
* Modern
* Professional
* Calm
* Secure
* Intuitive

Avoid unnecessary "hacker" aesthetics.

The visual identity should be consistent with **Sumnatic** while maintaining its own product identity.

### Brand

**SumnVault**

### Company

**Sumnatic**

### Tagline

> **Your files. One vault. Fully private.**

---

## 🚀 Getting Started

### Requirements

* Flutter SDK
* Dart SDK
* Platform-specific build dependencies
* Android SDK for Android development

Verify the Flutter environment:

```bash
flutter doctor
```

Clone the repository:

```bash
git clone <repository-url>
cd sumnvault
```

Install dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

For a specific platform:

```bash
flutter run -d windows
flutter run -d linux
flutter run -d macos
flutter run -d <android-device>
```

Build examples:

```bash
flutter build windows
flutter build linux
flutter build macos
flutter build apk
```

Platform-specific requirements may vary.

---

## ⚠️ Security Status

SumnVault should **not be considered independently security-audited** until a qualified security review has been performed.

Cryptographic software must be reviewed carefully before being trusted with highly sensitive information.

The project prioritizes:

1. Security
2. Data integrity
3. Reliability
4. Cross-platform compatibility
5. Performance
6. User experience
7. Visual design

---

## 📄 License

[CC0-1.0 license](https://github.com/sumnatic/sumnvault/blob/main/LICENSE)

---

<div align="center">

### SumnVault

**Your files. One vault. Fully private.**

Made by **Sumnatic** 🇧🇷

</div>
