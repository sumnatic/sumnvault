/**
 * SumnVault Container Engine v1 - Web / Client-Side Implementation
 * Fully binary-compatible with SumnVault Flutter / Dart specification.
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.SumnVault = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const MAGIC = new Uint8Array([0x53, 0x56, 0x4c, 0x54]); // 'SVLT'
  const MAJOR_VERSION = 1;
  const DEFAULT_CHUNK_SIZE = 4 * 1024 * 1024; // 4 MiB
  const SALT_LENGTH = 16;
  const NONCE_LENGTH = 12;
  const MAC_LENGTH = 16;
  const VAULT_ID_LENGTH = 16;

  // Base64 utilities
  function uint8ToBase64(bytes) {
    let binary = '';
    const len = bytes.byteLength;
    for (let i = 0; i < len; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  function base64ToUint8(b64) {
    const binary = atob(b64);
    const len = binary.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  function base64UrlEncode(bytes) {
    return uint8ToBase64(bytes)
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
  }

  function randomBytes(length) {
    const bytes = new Uint8Array(length);
    crypto.getRandomValues(bytes);
    return bytes;
  }

  function randomId() {
    return base64UrlEncode(randomBytes(16));
  }

  function readUint32BE(bytes, offset) {
    const view = new DataView(bytes.buffer, bytes.byteOffset + offset, 4);
    return view.getUint32(0, false);
  }

  function writeUint32BE(value) {
    const buffer = new ArrayBuffer(4);
    const view = new DataView(buffer);
    view.setUint32(0, value, false);
    return new Uint8Array(buffer);
  }

  function concatArrays(arrays) {
    let totalLength = 0;
    for (const arr of arrays) {
      totalLength += arr.length;
    }
    const result = new Uint8Array(totalLength);
    let offset = 0;
    for (const arr of arrays) {
      result.set(arr, offset);
      offset += arr.length;
    }
    return result;
  }

  function validateVaultName(name) {
    if (!name || name === '.' || name === '..' || name.includes('/') || name.includes('\\') || name.includes('\0')) {
      throw new Error('Invalid vault item name');
    }
    return name;
  }

  // Cryptographic operations
  async function deriveKey(password, salt, kdfParams) {
    const memory = (kdfParams && kdfParams.memory) || 19456;
    const iterations = (kdfParams && kdfParams.iterations) || 2;
    const parallelism = (kdfParams && kdfParams.parallelism) || 1;

    // Get hashwasm instance
    let hashwasmLib = typeof hashwasm !== 'undefined' ? hashwasm : (typeof window !== 'undefined' ? window.hashwasm : null);
    if (!hashwasmLib && typeof require === 'function') {
      try {
        const vm = require('vm');
        const fs = require('fs');
        const path = require('path');
        const code = fs.readFileSync(path.join(__dirname, 'vendor/argon2.umd.min.js'), 'utf8');
        const ctx = { window: {}, self: {}, globalThis: {}, TextEncoder, TextDecoder, WebAssembly };
        ctx.window = ctx;
        ctx.self = ctx;
        ctx.globalThis = ctx;
        vm.createContext(ctx);
        vm.runInContext(code, ctx);
        hashwasmLib = ctx.hashwasm;
      } catch (_) {}
    }

    if (!hashwasmLib || !hashwasmLib.argon2id) {
      throw new Error('Argon2id library (hash-wasm) is required to derive vault keys.');
    }

    const keyBytes = await hashwasmLib.argon2id({
      password: password,
      salt: salt,
      parallelism: parallelism,
      iterations: iterations,
      memorySize: memory,
      hashLength: 32,
      outputType: 'binary'
    });

    return crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'AES-GCM' },
      false,
      ['encrypt', 'decrypt']
    );
  }

  async function encryptAesGcm(cleartext, cryptoKey, aad) {
    const nonce = randomBytes(NONCE_LENGTH);
    const ciphertextWithTag = new Uint8Array(
      await crypto.subtle.encrypt(
        {
          name: 'AES-GCM',
          iv: nonce,
          additionalData: aad,
          tagLength: 128
        },
        cryptoKey,
        cleartext
      )
    );
    // WebCrypto returns ciphertext || tag (16 bytes)
    const tagStart = ciphertextWithTag.length - MAC_LENGTH;
    const ciphertext = ciphertextWithTag.subarray(0, tagStart);
    const mac = ciphertextWithTag.subarray(tagStart);

    return {
      nonce: nonce,
      mac: mac,
      ciphertext: ciphertext
    };
  }

  async function decryptAesGcm(nonce, mac, ciphertext, cryptoKey, aad) {
    // Recombine ciphertext and mac for WebCrypto
    const combined = new Uint8Array(ciphertext.length + mac.length);
    combined.set(ciphertext, 0);
    combined.set(mac, ciphertext.length);

    const decrypted = await crypto.subtle.decrypt(
      {
        name: 'AES-GCM',
        iv: nonce,
        additionalData: aad,
        tagLength: 128
      },
      cryptoKey,
      combined
    );

    return new Uint8Array(decrypted);
  }

  // ZLib compression using fflate
  function compressZlib(data) {
    const fflateLib = typeof fflate !== 'undefined' ? fflate : (typeof require === 'function' ? require('./vendor/fflate.umd.min.js') : null);
    if (!fflateLib || !fflateLib.zlibSync) {
      throw new Error('fflate compression library is required for vault operations.');
    }
    return fflateLib.zlibSync(data);
  }

  function decompressZlib(data) {
    const fflateLib = typeof fflate !== 'undefined' ? fflate : (typeof require === 'function' ? require('./vendor/fflate.umd.min.js') : null);
    if (!fflateLib || !fflateLib.unzlibSync) {
      throw new Error('fflate compression library is required for vault operations.');
    }
    return fflateLib.unzlibSync(data);
  }

  class VaultItem {
    constructor({ id, parentId, name, isDirectory, logicalSize }) {
      this.id = id;
      this.parentId = parentId || null;
      this.name = validateVaultName(name);
      this.isDirectory = Boolean(isDirectory);
      this.logicalSize = logicalSize || 0;
    }
  }

  class VaultSession {
    constructor({ vaultId, salt, key, kdfParams }) {
      this.vaultId = vaultId;
      this.salt = salt;
      this.key = key;
      this.kdfParams = kdfParams || { memory: 19456, iterations: 2, parallelism: 1 };
      this.items = new Map(); // id -> VaultItem
      this.contents = new Map(); // id -> Uint8Array
      this.locked = false;
    }

    get entries() {
      return Array.from(this.items.values());
    }

    _ensureUnlocked() {
      if (this.locked) throw new Error('Vault is locked');
    }

    addFolder(name, parentId = null) {
      this._ensureUnlocked();
      validateVaultName(name);
      const id = randomId();
      const folder = new VaultItem({
        id: id,
        parentId: parentId,
        name: name,
        isDirectory: true,
        logicalSize: 0
      });
      this.items.set(id, folder);
      return folder;
    }

    addFile(name, data, parentId = null) {
      this._ensureUnlocked();
      validateVaultName(name);
      const id = randomId();
      const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
      const file = new VaultItem({
        id: id,
        parentId: parentId,
        name: name,
        isDirectory: false,
        logicalSize: bytes.byteLength
      });
      this.items.set(id, file);
      this.contents.set(id, bytes);
      return file;
    }

    rename(id, newName) {
      this._ensureUnlocked();
      validateVaultName(newName);
      const item = this.items.get(id);
      if (!item) throw new Error('Item not found');
      item.name = newName;
    }

    move(id, newParentId) {
      this._ensureUnlocked();
      const item = this.items.get(id);
      if (!item) throw new Error('Item not found');
      if (newParentId) {
        const parent = this.items.get(newParentId);
        if (!parent || !parent.isDirectory) throw new Error('Destination folder not found');
        if (newParentId === id) throw new Error('An item cannot contain itself');
        let ancestor = newParentId;
        const visited = new Set();
        while (ancestor) {
          if (visited.has(ancestor) || ancestor === id) throw new Error('Cannot move folder inside its descendant');
          visited.add(ancestor);
          ancestor = this.items.get(ancestor)?.parentId;
        }
      }
      item.parentId = newParentId || null;
    }

    delete(id) {
      this._ensureUnlocked();
      const item = this.items.get(id);
      if (!item) throw new Error('Item not found');
      // Delete children recursively
      const children = Array.from(this.items.values()).filter(e => e.parentId === id);
      for (const child of children) {
        this.delete(child.id);
      }
      this.items.delete(id);
      this.contents.delete(id);
    }

    readFile(id) {
      this._ensureUnlocked();
      const item = this.items.get(id);
      if (!item || item.isDirectory) throw new Error('File not found');
      const data = this.contents.get(id);
      if (!data) throw new Error('File contents missing');
      return data;
    }

    verify() {
      this._ensureUnlocked();
      for (const item of this.items.values()) {
        validateVaultName(item.name);
        if (item.parentId && !this.items.has(item.parentId)) {
          throw new Error('Missing parent reference for ' + item.name);
        }
        if (!item.isDirectory) {
          const data = this.contents.get(item.id);
          if (!data || data.byteLength !== item.logicalSize) {
            throw new Error('File size mismatch for ' + item.name);
          }
        }
      }
      // Check for cycles
      for (const item of this.items.values()) {
        const visited = new Set();
        let ancestor = item.parentId;
        while (ancestor) {
          if (visited.has(ancestor)) throw new Error('Folder cycle detected');
          visited.add(ancestor);
          ancestor = this.items.get(ancestor)?.parentId;
        }
      }
      return true;
    }

    lock() {
      if (this.locked) return;
      for (const data of this.contents.values()) {
        data.fill(0);
      }
      this.contents.clear();
      this.items.clear();
      this.key = null;
      this.locked = true;
    }

    async exportContainer() {
      this._ensureUnlocked();
      const textEncoder = new TextEncoder();

      // 1. Encrypt file chunks
      const counts = {};
      const chunkRecords = [];

      for (const item of this.items.values()) {
        if (item.isDirectory) continue;
        const fileBytes = this.readFile(item.id);
        let sequence = 0;
        let offset = 0;

        while (offset < fileBytes.byteLength || (fileBytes.byteLength === 0 && sequence === 0)) {
          const chunkClear = fileBytes.subarray(offset, Math.min(offset + DEFAULT_CHUNK_SIZE, fileBytes.byteLength));
          const compressed = compressZlib(chunkClear);

          // Chunk AAD: [...vaultId, ...utf8(id), sequence]
          const idBytes = textEncoder.encode(item.id);
          const aad = new Uint8Array(this.vaultId.length + idBytes.length + 1);
          aad.set(this.vaultId, 0);
          aad.set(idBytes, this.vaultId.length);
          aad[aad.length - 1] = sequence & 0xff;

          const enc = await encryptAesGcm(compressed, this.key, aad);
          const payload = concatArrays([enc.nonce, enc.mac, enc.ciphertext]);

          chunkRecords.push(writeUint32BE(payload.length));
          chunkRecords.push(payload);

          sequence++;
          offset += DEFAULT_CHUNK_SIZE;
          if (fileBytes.byteLength === 0) break;
        }

        counts[item.id] = sequence;
      }

      // 2. Build and encrypt manifest
      const manifestObj = {
        items: Array.from(this.items.values()).map(it => ({
          id: it.id,
          parentId: it.parentId,
          name: it.name,
          directory: it.isDirectory,
          size: it.logicalSize
        })),
        chunks: {}
      };
      for (const [id, count] of Object.entries(counts)) {
        manifestObj.chunks[id] = { count: count, compression: 'zlib' };
      }

      const manifestBytes = textEncoder.encode(JSON.stringify(manifestObj));
      const manifestAad = new Uint8Array(this.vaultId.length + 2);
      manifestAad.set(this.vaultId, 0);
      manifestAad[this.vaultId.length] = 1;
      manifestAad[this.vaultId.length + 1] = 0;

      const encManifest = await encryptAesGcm(manifestBytes, this.key, manifestAad);
      const manifestPayloadStr = JSON.stringify({
        nonce: uint8ToBase64(encManifest.nonce),
        mac: uint8ToBase64(encManifest.mac),
        cipher: uint8ToBase64(encManifest.ciphertext)
      });
      const manifestPayloadBytes = textEncoder.encode(manifestPayloadStr);

      // 3. Build cleartext header
      const headerObj = {
        version: 1,
        salt: uint8ToBase64(this.salt),
        id: uint8ToBase64(this.vaultId),
        kdf: {
          memory: this.kdfParams.memory,
          iterations: this.kdfParams.iterations,
          parallelism: this.kdfParams.parallelism
        }
      };
      const headerBytes = textEncoder.encode(JSON.stringify(headerObj));

      // 4. Assemble container
      const parts = [
        MAGIC,
        new Uint8Array([MAJOR_VERSION]),
        writeUint32BE(headerBytes.length),
        headerBytes,
        writeUint32BE(manifestPayloadBytes.length),
        manifestPayloadBytes,
        ...chunkRecords
      ];

      return concatArrays(parts);
    }
  }

  // Vault Engine
  const VaultEngine = {
    async create(vaultName, password, kdfOptions) {
      const salt = randomBytes(SALT_LENGTH);
      const vaultId = randomBytes(VAULT_ID_LENGTH);
      const kdf = {
        memory: (kdfOptions && kdfOptions.memory) || 19456,
        iterations: (kdfOptions && kdfOptions.iterations) || 2,
        parallelism: (kdfOptions && kdfOptions.parallelism) || 1
      };
      const key = await deriveKey(password, salt, kdf);
      return new VaultSession({
        vaultId: vaultId,
        salt: salt,
        key: key,
        kdfParams: kdf
      });
    },

    async open(containerBuffer, password) {
      const bytes = containerBuffer instanceof Uint8Array ? containerBuffer : new Uint8Array(containerBuffer);
      if (bytes.length < 9) throw new Error('File too small to be a valid SumnVault container');

      // Check magic 'SVLT'
      for (let i = 0; i < 4; i++) {
        if (bytes[i] !== MAGIC[i]) throw new Error('Unsupported vault format (invalid magic)');
      }

      const major = bytes[4];
      if (major !== 1) throw new Error('Unsupported vault version: ' + major);

      const headerLen = readUint32BE(bytes, 5);
      if (headerLen === 0 || headerLen > 64 * 1024) throw new Error('Invalid vault header length');

      const headerStart = 9;
      const headerEnd = headerStart + headerLen;
      if (headerEnd > bytes.length) throw new Error('Corrupt vault header');

      const textDecoder = new TextDecoder();
      const textEncoder = new TextEncoder();
      const header = JSON.parse(textDecoder.decode(bytes.subarray(headerStart, headerEnd)));

      const salt = base64ToUint8(header.salt);
      const vaultId = base64ToUint8(header.id);
      const kdf = header.kdf || { memory: 19456, iterations: 2, parallelism: 1 };

      const manifestLenPos = headerEnd;
      if (manifestLenPos + 4 > bytes.length) throw new Error('Corrupt vault manifest length');
      const manifestLen = readUint32BE(bytes, manifestLenPos);
      if (manifestLen === 0 || manifestLen > 64 * 1024 * 1024) throw new Error('Invalid manifest length');

      const manifestPayloadStart = manifestLenPos + 4;
      const manifestPayloadEnd = manifestPayloadStart + manifestLen;
      if (manifestPayloadEnd > bytes.length) throw new Error('Corrupt vault manifest payload');

      const manifestRecord = JSON.parse(textDecoder.decode(bytes.subarray(manifestPayloadStart, manifestPayloadEnd)));

      // Derive key
      const key = await deriveKey(password, salt, kdf);

      // Decrypt manifest
      const manifestNonce = base64ToUint8(manifestRecord.nonce);
      const manifestMac = base64ToUint8(manifestRecord.mac);
      const manifestCipher = base64ToUint8(manifestRecord.cipher);

      const manifestAad = new Uint8Array(vaultId.length + 2);
      manifestAad.set(vaultId, 0);
      manifestAad[vaultId.length] = 1;
      manifestAad[vaultId.length + 1] = 0;

      let clearManifestBytes;
      try {
        clearManifestBytes = await decryptAesGcm(manifestNonce, manifestMac, manifestCipher, key, manifestAad);
      } catch (err) {
        throw new Error('Incorrect password or damaged vault manifest');
      }

      const manifest = JSON.parse(textDecoder.decode(clearManifestBytes));

      const session = new VaultSession({
        vaultId: vaultId,
        salt: salt,
        key: key,
        kdfParams: kdf
      });

      // Populate items
      for (const item of manifest.items) {
        session.items.set(item.id, new VaultItem({
          id: item.id,
          parentId: item.parentId,
          name: item.name,
          isDirectory: item.directory,
          logicalSize: item.size
        }));
      }

      // Read chunk records
      let currentPos = manifestPayloadEnd;
      const chunksDescriptor = manifest.chunks || {};

      for (const item of session.items.values()) {
        if (item.isDirectory) continue;
        const desc = chunksDescriptor[item.id] || { count: 0 };
        const chunkCount = typeof desc === 'number' ? desc : (desc.count || 0);
        const isZlib = typeof desc === 'object' && desc.compression === 'zlib';

        const fileParts = [];
        const idBytes = textEncoder.encode(item.id);

        for (let seq = 0; seq < chunkCount; seq++) {
          if (currentPos + 4 > bytes.length) throw new Error('Truncated chunk record');
          const chunkLen = readUint32BE(bytes, currentPos);
          currentPos += 4;
          if (chunkLen < 28 || currentPos + chunkLen > bytes.length) throw new Error('Invalid chunk record');

          const nonce = bytes.subarray(currentPos, currentPos + 12);
          const mac = bytes.subarray(currentPos + 12, currentPos + 28);
          const ciphertext = bytes.subarray(currentPos + 28, currentPos + chunkLen);
          currentPos += chunkLen;

          // Chunk AAD: [...vaultId, ...utf8(id), seq]
          const aad = new Uint8Array(vaultId.length + idBytes.length + 1);
          aad.set(vaultId, 0);
          aad.set(idBytes, vaultId.length);
          aad[aad.length - 1] = seq & 0xff;

          let clearChunk;
          try {
            clearChunk = await decryptAesGcm(nonce, mac, ciphertext, key, aad);
          } catch (e) {
            throw new Error(`Authentication failure on chunk ${seq} of item "${item.name}"`);
          }

          if (isZlib) {
            clearChunk = decompressZlib(clearChunk);
          }
          fileParts.push(clearChunk);
        }

        const assembled = concatArrays(fileParts);
        session.contents.set(item.id, assembled);
      }

      session.verify();
      return session;
    }
  };

  return {
    VaultEngine: VaultEngine,
    VaultSession: VaultSession,
    VaultItem: VaultItem
  };
});
