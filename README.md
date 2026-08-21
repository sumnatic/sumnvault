# SumnVault

**SumnVault** is a secure, portable, encrypted file vault written in Python.

It allows you to store documents, certificates, credentials, recovery codes, source code, backups, and virtually any type of file inside a single `.sumn` file.

Your vault can be copied to a USB drive, external disk, cloud storage, or another computer while remaining protected by your password.

> **One file. One password. Your data.**

---

## Features

* 🔐 Strong password-based encryption
* 🧂 Unique cryptographic salt per vault
* 🛡️ Authenticated encryption and integrity verification
* 📦 Compression before encryption
* 📁 Support for directories and nested files
* ➕ Add files and directories
* 🗑️ Remove files
* ✏️ Rename and move files
* 📤 Export individual files or the entire vault
* 🔎 Search files inside the vault
* 🔑 Change the vault password
* 💾 Portable `.sumn` vault format
* ⚡ Designed to avoid loading entire vaults into memory
* 💥 Protection against corrupted or tampered vaults
* 🧩 Versioned file format for future compatibility
* 🖥️ CLI-first architecture with GUI support planned

---

## Why SumnVault?

Modern computers accumulate a huge amount of sensitive data:

* Personal documents
* Certificates
* Backup codes
* Recovery keys
* Credentials
* Private source code
* Financial documents
* Scanned documents
* Personal archives
* Configuration files

Keeping these files scattered across folders, drives, and cloud services makes organization and protection difficult.

SumnVault provides a simple alternative:

```text
Documents
Certificates
Recovery Codes
Backups
Private Files
       │
       ▼
┌─────────────────┐
│  SumnVault      │
│  myvault.sumn   │
└─────────────────┘
```

Everything is stored inside one encrypted container.

---

## Security

Security is the primary design goal of SumnVault.

The project is designed around established cryptographic primitives rather than custom cryptography.

A simplified representation of the key derivation process is:

```text
                 User Password
                       │
                       ▼
                    Argon2id
                       │
                Derived Key
                       │
                       ▼
             Authenticated Encryption
                       │
                       ▼
                  .sumn Vault
```

The vault is designed to provide:

* Password-based key derivation
* Protection against offline password guessing
* Confidentiality of stored files
* Integrity verification
* Tamper detection
* Encrypted vault metadata
* Secure random salts and nonces
* Safe vault updates
* Atomic writes where possible

### Important

SumnVault does **not** store your password.

If you lose your password, there is intentionally no hidden master password or backdoor that can recover the vault.

**Your password is your key.**

Always keep secure backups of your `.sumn` files.

---

## Example

Create a vault:

```bash
sumnvault create personal.sumn
```

Add a file:

```bash
sumnvault add personal.sumn certificate.pdf
```

Add an entire directory:

```bash
sumnvault add personal.sumn ./documents/
```

List its contents:

```bash
sumnvault list personal.sumn
```

Extract a file:

```bash
sumnvault extract personal.sumn certificate.pdf
```

Export the entire vault:

```bash
sumnvault export personal.sumn ./backup/
```

Change the password:

```bash
sumnvault passwd personal.sumn
```

---

## Interactive Mode

SumnVault can also provide an interactive shell for working with an unlocked vault:

```text
SumnVault
Version 1

Password: ********

Vault unlocked.

12 files
4 directories
Size: 184 MB

sumnvault>
```

Available commands may include:

```text
ls
cd
pwd
add
mkdir
rm
mv
rename
extract
cat
info
search
export
passwd
lock
exit
```

---

## `.sumn` Format

SumnVault uses its own versioned container format.

Conceptually:

```text
┌──────────────────────────────┐
│          SUMN HEADER         │
├──────────────────────────────┤
│     Encrypted Metadata       │
├──────────────────────────────┤
│                              │
│     Compressed File Data     │
│                              │
├──────────────────────────────┤
│ Integrity / Authentication   │
└──────────────────────────────┘
```

Sensitive metadata should remain encrypted so that inspecting a `.sumn` file does not unnecessarily reveal its contents.

The format is versioned to allow future versions of SumnVault to evolve without immediately breaking existing vaults.

---

## Architecture

SumnVault is designed with separation between the user interface and the vault engine:

```text
CLI / GUI
    │
    ▼
Vault API
    │
    ▼
Vault Engine
    │
    ├── Storage
    ├── Metadata
    ├── Compression
    └── Cryptography
```

This allows future interfaces and features to be added without rewriting the underlying vault engine.

---

## Installation

Clone the repository:

```bash
git clone https://github.com/sumnatic/sumnvault.git
cd sumnvault
```

Install the project:

```bash
pip install .
```

For development:

```bash
pip install -e ".[dev]"
```

---

## Design Goals

SumnVault prioritizes:

1. **Security**
2. **Integrity**
3. **Reliability**
4. **Privacy**
5. **Efficiency**
6. **Usability**

The project is intended to remain simple enough for individuals to use while maintaining a security-oriented architecture.

---

## Threat Model

SumnVault is designed primarily to protect data stored at rest.

For example, it should help protect a `.sumn` file if someone obtains a copy of it without knowing the password.

However, it cannot protect against every possible threat.

SumnVault cannot reliably protect your data if:

* Your password is compromised
* Your computer is already compromised
* Malware can access your unlocked vault
* Your operating system is compromised
* You voluntarily export decrypted files to an insecure location
* Your password is weak enough to be practically guessed

Security is not just about encryption. Use a strong, unique password and keep backups of your vault.

---

## Philosophy

SumnVault follows a simple principle:

> **Your files should belong to you, not to the application that stores them.**

The `.sumn` format is designed to make an encrypted vault portable, self-contained, and independent of a particular folder structure or cloud provider.

Copy the vault.

Move the vault.

Back up the vault.

Keep control of the vault.

---

## License

SumnVault is released under the **MIT License**.

See [`LICENSE`](LICENSE) for details.

---

