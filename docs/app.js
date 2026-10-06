/**
 * SumnVault Web - Application Controller
 * Handles UI interactions, drag-and-drop, modals, previews, and vault operations.
 */
(function () {
  'use strict';

  // Application State
  const state = {
    session: null,
    vaultName: 'Personal',
    currentFolderId: null,
    pendingOpenFile: null, // { name, buffer }
    activeModal: null,
    previewItem: null,
    previewObjectUrl: null,
    itemToDelete: null,
    itemToRename: null,
    unsavedChanges: false,
    autoLockTimer: null,
    autoLockMinutes: 15
  };

  // DOM Elements
  const el = {
    viewWelcome: document.getElementById('view-welcome'),
    viewBrowser: document.getElementById('view-browser'),
    headerControls: document.getElementById('header-vault-controls'),
    currentVaultTitle: document.getElementById('current-vault-title'),
    btnHeaderSave: document.getElementById('btn-header-save'),
    btnHeaderLock: document.getElementById('btn-header-lock'),
    btnLockBrowser: document.getElementById('btn-lock-browser'),

    // Welcome view
    dropzoneOpen: document.getElementById('dropzone-open'),
    inputOpenFile: document.getElementById('input-open-file'),
    formCreateVault: document.getElementById('form-create-vault'),
    inputNewName: document.getElementById('input-new-name'),
    inputNewPassword: document.getElementById('input-new-password'),
    toggleNewPw: document.getElementById('toggle-new-pw'),

    // Browser view
    browserBreadcrumbs: document.getElementById('browser-breadcrumbs'),
    browserSearch: document.getElementById('browser-search'),
    itemsGrid: document.getElementById('items-grid'),
    btnImportFiles: document.getElementById('btn-import-files'),
    inputImportFiles: document.getElementById('input-import-files'),
    btnAddFolder: document.getElementById('btn-add-folder'),
    btnDownloadVault: document.getElementById('btn-download-vault'),
    dropzoneBrowserOverlay: document.getElementById('dropzone-browser-overlay'),

    // Modals
    modalUnlock: document.getElementById('modal-unlock'),
    unlockFileName: document.getElementById('unlock-file-name'),
    inputUnlockPassword: document.getElementById('input-unlock-password'),
    toggleUnlockPw: document.getElementById('toggle-unlock-pw'),
    unlockStatus: document.getElementById('unlock-status'),
    btnConfirmUnlock: document.getElementById('btn-confirm-unlock'),
    btnCancelUnlock: document.getElementById('btn-cancel-unlock'),
    btnCloseUnlock: document.getElementById('btn-close-unlock'),

    modalPreview: document.getElementById('modal-preview'),
    previewFileTitle: document.getElementById('preview-file-title'),
    previewFileSize: document.getElementById('preview-file-size'),
    previewViewport: document.getElementById('preview-viewport'),
    btnPreviewDownload: document.getElementById('btn-preview-download'),
    btnFooterDownload: document.getElementById('btn-footer-download'),
    btnDismissPreview: document.getElementById('btn-dismiss-preview'),
    btnClosePreview: document.getElementById('btn-close-preview'),

    modalFolder: document.getElementById('modal-folder'),
    inputFolderName: document.getElementById('input-folder-name'),
    btnConfirmFolder: document.getElementById('btn-confirm-folder'),
    btnCancelFolder: document.getElementById('btn-cancel-folder'),
    btnCloseFolder: document.getElementById('btn-close-folder'),

    modalRename: document.getElementById('modal-rename'),
    inputRenameName: document.getElementById('input-rename-name'),
    btnConfirmRename: document.getElementById('btn-confirm-rename'),
    btnCancelRename: document.getElementById('btn-cancel-rename'),
    btnCloseRename: document.getElementById('btn-close-rename'),

    modalDelete: document.getElementById('modal-delete'),
    deletePromptText: document.getElementById('delete-prompt-text'),
    btnConfirmDelete: document.getElementById('btn-confirm-delete'),
    btnCancelDelete: document.getElementById('btn-cancel-delete'),
    btnCloseDelete: document.getElementById('btn-close-delete'),

    toastContainer: document.getElementById('toast-container')
  };

  // Utilities
  function showToast(message, type = 'success') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `
      <span>${type === 'error' ? '⚠️' : '✓'}</span>
      <div>${escapeHtml(message)}</div>
    `;
    el.toastContainer.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(10px)';
      toast.style.transition = 'all 0.3s ease';
      setTimeout(() => toast.remove(), 300);
    }, 3500);
  }

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  }

  function getFileCategory(filename) {
    const ext = (filename.split('.').pop() || '').toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp', 'ico'].includes(ext)) return 'image';
    if (['txt', 'json', 'js', 'html', 'css', 'dart', 'py', 'java', 'c', 'cpp', 'rs', 'md', 'xml', 'yaml', 'yml', 'sh', 'ps1'].includes(ext)) return 'code';
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'csv'].includes(ext)) return 'document';
    if (['mp3', 'wav', 'ogg', 'm4a', 'flac', 'aac'].includes(ext)) return 'audio';
    if (['mp4', 'webm', 'mov', 'mkv', 'avi'].includes(ext)) return 'video';
    if (['zip', 'tar', 'gz', '7z', 'rar', 'bz2'].includes(ext)) return 'archive';
    return 'generic';
  }

  function getFileIcon(filename) {
    const cat = getFileCategory(filename);
    if (cat === 'image') {
      return `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>`;
    }
    if (cat === 'code') {
      return `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>`;
    }
    if (cat === 'document') {
      return `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>`;
    }
    if (cat === 'audio' || cat === 'video') {
      return `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg>`;
    }
    return `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><polyline points="13 2 13 9 20 9"/></svg>`;
  }

  // Activity & Auto-Lock Timer
  function resetAutoLock() {
    clearTimeout(state.autoLockTimer);
    if (state.session && !state.session.locked) {
      state.autoLockTimer = setTimeout(() => {
        lockVault();
        showToast('Vault auto-locked due to inactivity.', 'error');
      }, state.autoLockMinutes * 60 * 1000);
    }
  }

  ['mousemove', 'keydown', 'mousedown', 'touchstart', 'scroll'].forEach(evt => {
    window.addEventListener(evt, resetAutoLock, { passive: true });
  });

  // Modal helpers
  function openModal(modalEl) {
    if (state.activeModal) closeModal(state.activeModal);
    modalEl.classList.add('active');
    state.activeModal = modalEl;
  }

  function closeModal(modalEl) {
    if (!modalEl) return;
    modalEl.classList.remove('active');
    if (state.activeModal === modalEl) state.activeModal = null;
    if (modalEl === el.modalPreview && state.previewObjectUrl) {
      URL.revokeObjectURL(state.previewObjectUrl);
      state.previewObjectUrl = null;
    }
  }

  // Switch Views
  function showView(viewId) {
    el.viewWelcome.classList.remove('active');
    el.viewBrowser.classList.remove('active');

    if (viewId === 'browser') {
      el.viewBrowser.classList.add('active');
      el.headerControls.style.display = 'flex';
      el.currentVaultTitle.textContent = state.vaultName.endsWith('.svault') ? state.vaultName : state.vaultName + '.svault';
    } else {
      el.viewWelcome.classList.add('active');
      el.headerControls.style.display = 'none';
    }
  }

  // File Handling (Opening a vault)
  function handleSelectVaultFile(file) {
    if (!file) return;
    if (!file.name.toLowerCase().endsWith('.svault')) {
      showToast('Please select a valid .svault container file.', 'error');
      return;
    }

    const reader = new FileReader();
    reader.onload = function (e) {
      state.pendingOpenFile = {
        name: file.name,
        buffer: new Uint8Array(e.target.result)
      };
      el.unlockFileName.textContent = file.name;
      el.inputUnlockPassword.value = '';
      el.unlockStatus.textContent = '';
      openModal(el.modalUnlock);
      setTimeout(() => el.inputUnlockPassword.focus(), 100);
    };
    reader.onerror = function () {
      showToast('Error reading the selected file.', 'error');
    };
    reader.readAsArrayBuffer(file);
  }

  // Create Vault
  async function handleCreateVault() {
    const name = el.inputNewName.value.trim() || 'Personal';
    const password = el.inputNewPassword.value;

    if (!password) {
      showToast('Please choose a master password.', 'error');
      el.inputNewPassword.focus();
      return;
    }

    const btn = document.getElementById('btn-create-submit');
    const originalText = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = `<span class="spinner"></span> Creating...`;

    try {
      state.session = await SumnVault.VaultEngine.create(name, password);
      state.vaultName = name;
      state.currentFolderId = null;
      state.unsavedChanges = true;

      showToast(`Vault "${name}" created successfully!`);
      showView('browser');
      renderBrowser();
      resetAutoLock();
    } catch (err) {
      showToast('Failed to create vault: ' + err.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = originalText;
    }
  }

  // Unlock Vault
  async function handleUnlockVault() {
    if (!state.pendingOpenFile) return;
    const password = el.inputUnlockPassword.value;
    if (!password) {
      el.unlockStatus.textContent = 'Password cannot be empty.';
      el.unlockStatus.style.color = 'var(--accent-danger)';
      return;
    }

    el.btnConfirmUnlock.disabled = true;
    el.unlockStatus.innerHTML = `<span class="spinner" style="display:inline-block;vertical-align:middle;margin-right:6px;"></span> Deriving key with Argon2id...`;
    el.unlockStatus.style.color = 'var(--text-secondary)';

    // Use requestAnimationFrame to let the UI render the spinner before WASM runs
    requestAnimationFrame(async () => {
      try {
        state.session = await SumnVault.VaultEngine.open(state.pendingOpenFile.buffer, password);
        state.vaultName = state.pendingOpenFile.name.replace(/\.svault$/i, '');
        state.currentFolderId = null;
        state.unsavedChanges = false;
        state.pendingOpenFile = null;

        closeModal(el.modalUnlock);
        showToast('Vault unlocked successfully!');
        showView('browser');
        renderBrowser();
        resetAutoLock();
      } catch (err) {
        el.unlockStatus.textContent = 'Unable to unlock: ' + err.message;
        el.unlockStatus.style.color = 'var(--accent-danger)';
      } finally {
        el.btnConfirmUnlock.disabled = false;
      }
    });
  }

  // Lock Vault
  function lockVault() {
    if (state.session) {
      state.session.lock();
      state.session = null;
    }
    state.vaultName = 'Personal';
    state.currentFolderId = null;
    state.pendingOpenFile = null;
    state.unsavedChanges = false;
    clearTimeout(state.autoLockTimer);

    if (state.activeModal) closeModal(state.activeModal);
    showView('welcome');
    showToast('Vault locked.');
  }

  // Save / Download Vault
  async function handleSaveVault() {
    if (!state.session) return;
    const btn = el.btnHeaderSave;
    const origHtml = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = `<span class="spinner"></span> Saving...`;

    try {
      const containerBytes = await state.session.exportContainer();
      const blob = new Blob([containerBytes], { type: 'application/x-sumnvault' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = state.vaultName.endsWith('.svault') ? state.vaultName : state.vaultName + '.svault';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);

      state.unsavedChanges = false;
      showToast('Vault container saved and downloaded!');
    } catch (err) {
      showToast('Failed to save vault: ' + err.message, 'error');
    } finally {
      btn.disabled = false;
      btn.innerHTML = origHtml;
    }
  }

  // Import Files
  async function handleImportFiles(files) {
    if (!state.session || !files || files.length === 0) return;
    let importedCount = 0;

    for (const file of files) {
      try {
        const arrayBuf = await file.arrayBuffer();
        state.session.addFile(file.name, new Uint8Array(arrayBuf), state.currentFolderId);
        importedCount++;
      } catch (e) {
        showToast(`Error importing ${file.name}: ${e.message}`, 'error');
      }
    }

    if (importedCount > 0) {
      state.unsavedChanges = true;
      showToast(`Imported ${importedCount} file${importedCount > 1 ? 's' : ''}. Remember to save .svault!`);
      renderBrowser();
    }
  }

  // Add Folder
  function handleAddFolder() {
    const name = el.inputFolderName.value.trim();
    if (!name) return;
    try {
      state.session.addFolder(name, state.currentFolderId);
      state.unsavedChanges = true;
      closeModal(el.modalFolder);
      showToast(`Folder "${name}" created.`);
      renderBrowser();
    } catch (e) {
      showToast('Error creating folder: ' + e.message, 'error');
    }
  }

  // Rename
  function handleConfirmRename() {
    if (!state.itemToRename) return;
    const newName = el.inputRenameName.value.trim();
    if (!newName) return;
    try {
      state.session.rename(state.itemToRename.id, newName);
      state.unsavedChanges = true;
      closeModal(el.modalRename);
      showToast(`Renamed to "${newName}".`);
      renderBrowser();
    } catch (e) {
      showToast('Error renaming item: ' + e.message, 'error');
    }
  }

  // Delete
  function handleConfirmDelete() {
    if (!state.itemToDelete) return;
    try {
      const name = state.itemToDelete.name;
      state.session.delete(state.itemToDelete.id);
      state.unsavedChanges = true;
      closeModal(el.modalDelete);
      showToast(`"${name}" deleted from vault.`);
      renderBrowser();
    } catch (e) {
      showToast('Error deleting item: ' + e.message, 'error');
    }
  }

  // Export Individual File
  function exportFile(item) {
    try {
      const data = state.session.readFile(item.id);
      const blob = new Blob([data], { type: 'application/octet-stream' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = item.name;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      showToast(`Exported "${item.name}"`);
    } catch (e) {
      showToast('Failed to export file: ' + e.message, 'error');
    }
  }

  // In-Browser Preview
  function previewFile(item) {
    if (item.isDirectory) return;
    state.previewItem = item;
    el.previewFileTitle.textContent = item.name;
    el.previewFileSize.textContent = formatBytes(item.logicalSize);
    el.previewViewport.innerHTML = '';

    try {
      const data = state.session.readFile(item.id);
      const category = getFileCategory(item.name);
      const ext = (item.name.split('.').pop() || '').toLowerCase();

      if (category === 'image') {
        const mime = ext === 'svg' ? 'image/svg+xml' : `image/${ext === 'jpg' ? 'jpeg' : ext}`;
        const blob = new Blob([data], { type: mime });
        state.previewObjectUrl = URL.createObjectURL(blob);
        el.previewViewport.innerHTML = `<img src="${state.previewObjectUrl}" alt="${escapeHtml(item.name)}">`;
      } else if (category === 'audio') {
        const blob = new Blob([data], { type: `audio/${ext}` });
        state.previewObjectUrl = URL.createObjectURL(blob);
        el.previewViewport.innerHTML = `<audio controls src="${state.previewObjectUrl}" style="width: 100%;"></audio>`;
      } else if (category === 'video') {
        const blob = new Blob([data], { type: `video/${ext}` });
        state.previewObjectUrl = URL.createObjectURL(blob);
        el.previewViewport.innerHTML = `<video controls src="${state.previewObjectUrl}" style="max-width: 100%; max-height: 50vh;"></video>`;
      } else if (category === 'code' || ext === 'txt' || ext === 'json' || ext === 'md' || ext === 'csv' || ext === 'log') {
        const text = new TextDecoder('utf-8', { fatal: false }).decode(data);
        el.previewViewport.innerHTML = `<pre><code>${escapeHtml(text)}</code></pre>`;
      } else if (ext === 'pdf') {
        const blob = new Blob([data], { type: 'application/pdf' });
        state.previewObjectUrl = URL.createObjectURL(blob);
        el.previewViewport.innerHTML = `<iframe src="${state.previewObjectUrl}" style="width: 100%; height: 500px; border: none; border-radius: 6px;"></iframe>`;
      } else {
        el.previewViewport.innerHTML = `
          <div style="text-align: center; padding: 32px 16px;">
            <div style="font-size: 3rem; margin-bottom: 12px;">📄</div>
            <div style="font-weight: 600; margin-bottom: 8px;">In-browser preview not available for .${escapeHtml(ext)} files.</div>
            <div style="color: var(--text-muted); font-size: 0.85rem; margin-bottom: 16px;">Click Download to open with your system's default application.</div>
          </div>
        `;
      }

      openModal(el.modalPreview);
    } catch (e) {
      showToast('Error loading preview: ' + e.message, 'error');
    }
  }

  // Render Browser View
  function renderBrowser() {
    if (!state.session) return;

    // 1. Render Breadcrumbs
    const crumbs = [];
    let curId = state.currentFolderId;
    while (curId) {
      const folder = state.session.items.get(curId);
      if (!folder) break;
      crumbs.unshift(folder);
      curId = folder.parentId;
    }

    let breadcrumbsHtml = `
      <button class="crumb-btn" data-folder-id="">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
        Home
      </button>
    `;

    crumbs.forEach((folder, idx) => {
      breadcrumbsHtml += `<span class="crumb-sep">/</span>`;
      if (idx === crumbs.length - 1) {
        breadcrumbsHtml += `<span class="crumb-current">${escapeHtml(folder.name)}</span>`;
      } else {
        breadcrumbsHtml += `<button class="crumb-btn" data-folder-id="${folder.id}">${escapeHtml(folder.name)}</button>`;
      }
    });

    el.browserBreadcrumbs.innerHTML = breadcrumbsHtml;

    // Attach crumb click listeners
    el.browserBreadcrumbs.querySelectorAll('.crumb-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        state.currentFolderId = btn.getAttribute('data-folder-id') || null;
        renderBrowser();
      });
    });

    // 2. Filter Items in Current Folder
    const searchQuery = el.browserSearch.value.trim().toLowerCase();
    const allInFolder = state.session.entries.filter(item => {
      if (searchQuery) {
        // When searching, match across current folder
        return item.parentId === state.currentFolderId && item.name.toLowerCase().includes(searchQuery);
      }
      return item.parentId === state.currentFolderId;
    });

    // Sort: Folders first, then files alphabetically
    allInFolder.sort((a, b) => {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
    });

    // 3. Render Cards
    if (allInFolder.length === 0) {
      el.itemsGrid.innerHTML = `
        <div class="empty-state">
          <div class="empty-icon">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
          </div>
          <div class="empty-title">This folder is empty</div>
          <div class="empty-desc">Import files using the button above or drag & drop files directly into this window.</div>
        </div>
      `;
      return;
    }

    el.itemsGrid.innerHTML = '';
    allInFolder.forEach(item => {
      const card = document.createElement('div');
      card.className = 'vault-item-card';

      if (item.isDirectory) {
        const childCount = state.session.entries.filter(e => e.parentId === item.id).length;
        card.innerHTML = `
          <div class="item-left">
            <div class="item-icon-wrapper folder">
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
            </div>
            <div class="item-details">
              <div class="item-name" title="${escapeHtml(item.name)}">${escapeHtml(item.name)}</div>
              <div class="item-meta">${childCount} item${childCount !== 1 ? 's' : ''}</div>
            </div>
          </div>
          <div class="item-actions">
            <button class="action-btn-sm rename" title="Rename folder">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
            </button>
            <button class="action-btn-sm delete" title="Delete folder">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            </button>
          </div>
        `;

        // Click card navigates into folder
        card.querySelector('.item-left').addEventListener('click', () => {
          state.currentFolderId = item.id;
          renderBrowser();
        });
      } else {
        const cat = getFileCategory(item.name);
        card.innerHTML = `
          <div class="item-left">
            <div class="item-icon-wrapper file ${cat}">
              ${getFileIcon(item.name)}
            </div>
            <div class="item-details">
              <div class="item-name" title="${escapeHtml(item.name)}">${escapeHtml(item.name)}</div>
              <div class="item-meta">${formatBytes(item.logicalSize)}</div>
            </div>
          </div>
          <div class="item-actions">
            <button class="action-btn-sm preview" title="Quick Preview">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
            </button>
            <button class="action-btn-sm download" title="Download / Export">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
            </button>
            <button class="action-btn-sm rename" title="Rename">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
            </button>
            <button class="action-btn-sm delete" title="Delete">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            </button>
          </div>
        `;

        // Click card opens preview
        card.querySelector('.item-left').addEventListener('click', () => previewFile(item));
        card.querySelector('.preview').addEventListener('click', (e) => { e.stopPropagation(); previewFile(item); });
        card.querySelector('.download').addEventListener('click', (e) => { e.stopPropagation(); exportFile(item); });
      }

      // Rename button
      card.querySelector('.rename').addEventListener('click', (e) => {
        e.stopPropagation();
        state.itemToRename = item;
        el.inputRenameName.value = item.name;
        openModal(el.modalRename);
        setTimeout(() => el.inputRenameName.focus(), 100);
      });

      // Delete button
      card.querySelector('.delete').addEventListener('click', (e) => {
        e.stopPropagation();
        state.itemToDelete = item;
        el.deletePromptText.textContent = item.isDirectory
          ? `Delete folder "${item.name}" and all its contents?`
          : `Delete file "${item.name}" from vault?`;
        openModal(el.modalDelete);
      });

      el.itemsGrid.appendChild(card);
    });
  }

  // Event Listeners Initialization
  function initListeners() {
    // 1. Open Vault Dropzone & File Input
    el.dropzoneOpen.addEventListener('click', () => el.inputOpenFile.click());
    el.inputOpenFile.addEventListener('change', (e) => {
      if (e.target.files.length > 0) handleSelectVaultFile(e.target.files[0]);
      e.target.value = '';
    });

    ['dragenter', 'dragover'].forEach(evt => {
      el.dropzoneOpen.addEventListener(evt, (e) => {
        e.preventDefault();
        el.dropzoneOpen.classList.add('dragover');
      });
    });
    ['dragleave', 'drop'].forEach(evt => {
      el.dropzoneOpen.addEventListener(evt, (e) => {
        e.preventDefault();
        el.dropzoneOpen.classList.remove('dragover');
      });
    });
    el.dropzoneOpen.addEventListener('drop', (e) => {
      if (e.dataTransfer.files.length > 0) {
        handleSelectVaultFile(e.dataTransfer.files[0]);
      }
    });

    // 2. Global Window Drag & Drop (for opening .svault or importing files)
    window.addEventListener('dragover', (e) => e.preventDefault());
    window.addEventListener('drop', (e) => {
      e.preventDefault();
      if (!e.dataTransfer.files || e.dataTransfer.files.length === 0) return;

      if (!state.session) {
        // If not in a session, open the dropped .svault
        handleSelectVaultFile(e.dataTransfer.files[0]);
      } else {
        // If inside a session, import the dropped files!
        handleImportFiles(e.dataTransfer.files);
      }
    });

    // 3. Create Vault Form
    el.formCreateVault.addEventListener('submit', (e) => {
      e.preventDefault();
      handleCreateVault();
    });

    el.toggleNewPw.addEventListener('click', () => {
      el.inputNewPassword.type = el.inputNewPassword.type === 'password' ? 'text' : 'password';
    });

    // 4. Unlock Modal Controls
    el.btnConfirmUnlock.addEventListener('click', handleUnlockVault);
    el.inputUnlockPassword.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') handleUnlockVault();
    });
    el.toggleUnlockPw.addEventListener('click', () => {
      el.inputUnlockPassword.type = el.inputUnlockPassword.type === 'password' ? 'text' : 'password';
    });
    el.btnCancelUnlock.addEventListener('click', () => closeModal(el.modalUnlock));
    el.btnCloseUnlock.addEventListener('click', () => closeModal(el.modalUnlock));

    // 5. Header Controls
    el.btnHeaderSave.addEventListener('click', handleSaveVault);
    el.btnDownloadVault.addEventListener('click', handleSaveVault);
    el.btnHeaderLock.addEventListener('click', lockVault);
    el.btnLockBrowser.addEventListener('click', lockVault);

    // 6. Import Files
    el.btnImportFiles.addEventListener('click', () => el.inputImportFiles.click());
    el.inputImportFiles.addEventListener('change', (e) => {
      handleImportFiles(e.target.files);
      e.target.value = '';
    });

    // 7. Add Folder Modal
    el.btnAddFolder.addEventListener('click', () => {
      el.inputFolderName.value = '';
      openModal(el.modalFolder);
      setTimeout(() => el.inputFolderName.focus(), 100);
    });
    el.btnConfirmFolder.addEventListener('click', handleAddFolder);
    el.inputFolderName.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') handleAddFolder();
    });
    el.btnCancelFolder.addEventListener('click', () => closeModal(el.modalFolder));
    el.btnCloseFolder.addEventListener('click', () => closeModal(el.modalFolder));

    // 8. Rename Modal
    el.btnConfirmRename.addEventListener('click', handleConfirmRename);
    el.inputRenameName.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') handleConfirmRename();
    });
    el.btnCancelRename.addEventListener('click', () => closeModal(el.modalRename));
    el.btnCloseRename.addEventListener('click', () => closeModal(el.modalRename));

    // 9. Delete Modal
    el.btnConfirmDelete.addEventListener('click', handleConfirmDelete);
    el.btnCancelDelete.addEventListener('click', () => closeModal(el.modalDelete));
    el.btnCloseDelete.addEventListener('click', () => closeModal(el.modalDelete));

    // 10. Preview Modal
    const downloadPreview = () => {
      if (state.previewItem) exportFile(state.previewItem);
    };
    el.btnPreviewDownload.addEventListener('click', downloadPreview);
    el.btnFooterDownload.addEventListener('click', downloadPreview);
    el.btnDismissPreview.addEventListener('click', () => closeModal(el.modalPreview));
    el.btnClosePreview.addEventListener('click', () => closeModal(el.modalPreview));

    // 11. Search Filter
    el.browserSearch.addEventListener('input', () => renderBrowser());

    // 12. Modal backdrop close on escape or click outside
    document.querySelectorAll('.modal-overlay').forEach(overlay => {
      overlay.addEventListener('click', (e) => {
        if (e.target === overlay) closeModal(overlay);
      });
    });

    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && state.activeModal) {
        closeModal(state.activeModal);
      }
    });

    // 13. Warn on page reload if unsaved changes
    window.addEventListener('beforeunload', (e) => {
      if (state.session && state.unsavedChanges) {
        e.preventDefault();
        e.returnValue = 'You have unsaved changes in your vault. Remember to download your .svault file.';
      }
    });
  }

  // Initialize
  initListeners();
})();
