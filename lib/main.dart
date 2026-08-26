import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sumnvault/core/vault/vault_engine.dart';
import 'package:sumnvault/core/vault/vault_format.dart';
import 'package:sumnvault/services/android_storage.dart';

void main() => runApp(const SumnVaultApp());

class SumnVaultApp extends StatelessWidget {
  const SumnVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData.dark();
    return MaterialApp(
      title: 'SumnVault',
      debugShowCheckedModeBanner: false,
      theme: dark.copyWith(
        scaffoldBackgroundColor: const Color(0xff0b100f),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4ed6b4), brightness: Brightness.dark),
        cardTheme: CardThemeData(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
      home: const VaultHome(),
    );
  }
}

class VaultHome extends StatefulWidget {
  const VaultHome({super.key});
  @override
  State<VaultHome> createState() => _VaultHomeState();
}

class _VaultHomeState extends State<VaultHome> {
  final engine = VaultEngine();
  final search = TextEditingController();
  final vaults = <VaultData>[
    VaultData('Personal.svault', 'Opened today', '24.2 MB', Icons.person_outline, Color(0xff4ed6b4)),
    VaultData('Documents.svault', 'Opened yesterday', '1.8 GB', Icons.description_outlined, Color(0xff8fb8ff)),
    VaultData('Projects.svault', 'Opened Aug 20', '640 MB', Icons.work_outline, Color(0xffffbd70)),
  ];

  @override
  void initState() {
    super.initState();
    _loadPersistedVaults();
  }

  Future<void> _loadPersistedVaults() async {
    final uris = await AndroidStorage.recentUris();
    if (!mounted) return;
    for (final uri in uris) {
      if (!vaults.any((vault) => vault.path == uri)) {
        setState(() => vaults.add(VaultData(uri.split('/').last, 'Available on this device', 'Unknown size', Icons.lock_outline, const Color(0xffd891ff), path: uri)));
      }
    }
  }

  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> _createVault() async {
    final details = await _passwordDialog('Create a vault');
    if (details == null || !mounted) return;
    final uri = await FilePicker.saveFile(dialogTitle: 'Choose vault location', fileName: '${details.$1}.svault', bytes: Uint8List(0), type: FileType.custom, allowedExtensions: ['svault']);
    final path = uri == null ? null : await AndroidStorage.prepareDestination(uri.toString());
    if (path == null || !mounted) return;
    final session = await engine.create(File(path), details.$2);
    if (uri != null) {
      await AndroidStorage.persistUri(uri.toString());
      await AndroidStorage.commitDocument(uri.toString(), path);
    }
    setState(() => vaults.insert(0, VaultData('${details.$1}.svault', 'Opened just now', '0 B', Icons.lock_outline, const Color(0xffd891ff), path: path)));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VaultBrowser(session: session, vaultName: details.$1, externalUri: uri?.toString(), onSaved: () => _message('Vault saved.'))));
  }

  Future<void> _openVault() async {
    // file_picker 12 does not expose pickFile yet; select one entry from the list API.
    // ignore: deprecated_member_use
    final picked = await FilePicker.pickFiles(dialogTitle: 'Open SumnVault', type: FileType.custom, allowedExtensions: ['svault'], allowMultiple: false);
    final selected = picked.isNotEmpty ? picked.first.path : null;
    final path = selected == null ? null : await AndroidStorage.importDocument(selected);
    if (path == null || !mounted) return;
    if (selected != null) await AndroidStorage.persistUri(selected);
    final password = await _passwordDialog('Unlock vault', nameOnly: true);
    if (password == null || !mounted) return;
    try {
      final opened = await engine.open(File(path), password.$2);
      await opened.verify();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VaultBrowser(session: opened, vaultName: File(path).uri.pathSegments.last, externalUri: selected, onSaved: () => _message('Vault saved.'))));
    } catch (_) {
      _message('Unable to unlock vault. The password may be incorrect, or the vault may be damaged.');
    }
  }

  Future<(String, String)?> _passwordDialog(String title, {bool nameOnly = false}) async {
    final name = TextEditingController(text: nameOnly ? 'Vault' : 'Personal');
    final password = TextEditingController();
    final result = await showDialog<(String, String)>(context: context, builder: (context) => AlertDialog(title: Text(title), content: Column(mainAxisSize: MainAxisSize.min, children: [if (!nameOnly) TextField(controller: name, decoration: const InputDecoration(labelText: 'Vault name')), TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password'))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, (name.text.trim(), password.text)), child: Text(nameOnly ? 'Unlock' : 'Create'))]));
    name.dispose();
    password.dispose();
    return result;
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final filtered = vaults.where((vault) => vault.name.toLowerCase().contains(search.text.toLowerCase())).toList();
        return Scaffold(
          appBar: compact ? AppBar(title: const Text('SumnVault', style: TextStyle(fontWeight: FontWeight.w700))) : null,
          bottomNavigationBar: compact ? NavigationBar(selectedIndex: 0, destinations: const [NavigationDestination(icon: Icon(Icons.grid_view_outlined), label: 'Vaults'), NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings')]) : null,
          body: Row(children: [if (!compact) const VaultSidebar(), Expanded(child: _content(context, compact, filtered))]),
        );
      });

  Widget _content(BuildContext context, bool compact, List<VaultData> filtered) {
    final side = compact ? 20.0 : 48.0;
    return CustomScrollView(slivers: [
      SliverPadding(padding: EdgeInsets.fromLTRB(side, compact ? 24 : 52, side, 28), sliver: SliverToBoxAdapter(child: _intro(context, compact))),
      SliverPadding(padding: EdgeInsets.symmetric(horizontal: side), sliver: SliverToBoxAdapter(child: Row(children: [Text('Recent vaults', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)), const Spacer(), Text('${filtered.length} vaults')]))),
      SliverPadding(padding: EdgeInsets.fromLTRB(side, 14, side, 48), sliver: SliverGrid(delegate: SliverChildBuilderDelegate((context, index) {
        final vault = filtered[index];
        return VaultCard(vault: vault, onOpen: vault.path == null ? null : () => _unlockKnownVault(vault));
      }, childCount: filtered.length), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 360, mainAxisExtent: 205, crossAxisSpacing: 16, mainAxisSpacing: 16))),
      SliverPadding(padding: EdgeInsets.fromLTRB(side, 0, side, 48), sliver: SliverToBoxAdapter(child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.verified_user_outlined), SizedBox(width: 14), Expanded(child: Text('Your vaults stay on this device. SumnVault works offline and never requires an account.'))])))),
    ]);
  }

  Widget _intro(BuildContext context, bool compact) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your private digital vaults', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('One file. Many files. One secure vault.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 32),
                Row(children: [Expanded(child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search vaults'))), const SizedBox(width: 12), FilledButton.icon(onPressed: _createVault, icon: const Icon(Icons.add), label: Text(compact ? 'New' : 'Create vault')), const SizedBox(width: 8), IconButton(onPressed: _openVault, icon: const Icon(Icons.folder_open_outlined), tooltip: 'Open vault')]),
      ]);

  Future<void> _unlockKnownVault(VaultData vault) async {
    final password = await _passwordDialog('Unlock ${vault.name}', nameOnly: true);
    if (password == null || vault.path == null || !mounted) return;
    try {
      final path = await AndroidStorage.importDocument(vault.path!);
      await AndroidStorage.persistUri(vault.path!);
      final session = await engine.open(File(path), password.$2);
      await session.verify();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VaultBrowser(session: session, vaultName: vault.name.replaceAll('.svault', ''), onSaved: () => _message('Vault saved.'))));
    } catch (_) {
      _message('Unable to unlock vault. Check the password or vault integrity.');
    }
  }
}

class VaultData {
  const VaultData(this.name, this.lastOpened, this.size, this.icon, this.color, {this.path});
  final String name;
  final String lastOpened;
  final String size;
  final IconData icon;
  final Color color;
  final String? path;
}

class VaultSidebar extends StatelessWidget {
  const VaultSidebar({super.key});
  @override
    Widget build(BuildContext context) => Container(width: 246, padding: const EdgeInsets.fromLTRB(20, 28, 16, 20), decoration: BoxDecoration(border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .35)))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.onPrimary)), const SizedBox(width: 10), const Expanded(child: Text('SumnVault', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))]),
        const SizedBox(height: 48),
        const ListTile(selected: true, leading: Icon(Icons.grid_view_outlined), title: Text('Vaults')),
        const ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings')),
        const Spacer(),
        Text('SUMNATIC  /  LOCAL-FIRST', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.1)),
      ]));
}

class VaultCard extends StatelessWidget {
  const VaultCard({super.key, required this.vault, this.onOpen});
  final VaultData vault;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onOpen ?? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use Open vault to choose this file.'))), child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: vault.color.withValues(alpha: .14), borderRadius: BorderRadius.circular(11)), child: Icon(vault.icon, color: vault.color)), const Spacer(), const Icon(Icons.lock_outline, size: 18)]),
        const Spacer(),
        Text(vault.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(children: [Expanded(child: Text(vault.lastOpened, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)), const SizedBox(width: 8), Text(vault.size, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))]),
      ]))));
}

class VaultBrowser extends StatefulWidget {
  const VaultBrowser({super.key, required this.session, required this.vaultName, required this.onSaved, this.externalUri});
  final VaultSession session;
  final String vaultName;
  final VoidCallback onSaved;
  final String? externalUri;

  @override
  State<VaultBrowser> createState() => _VaultBrowserState();
}

class _VaultBrowserState extends State<VaultBrowser> with WidgetsBindingObserver {
  String? folderId;
  bool busy = false;
  Timer? _autoLockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armAutoLock();
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _lockAndLeave();
  }

  void _armAutoLock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(const Duration(minutes: 15), _lockAndLeave);
  }

  void _lockAndLeave() {
    if (!mounted || widget.session.isLocked) return;
    widget.session.lock();
    Navigator.of(context).pop();
  }

  List<VaultItem> get currentItems => widget.session.entries.where((item) => item.parentId == folderId).toList();

  Future<void> _persist() async {
    await widget.session.save();
    if (widget.externalUri != null) await AndroidStorage.commitDocument(widget.externalUri!, widget.session.file.path);
    widget.onSaved();
  }

  Future<void> _importFile() async {
    // ignore: deprecated_member_use
    final picked = await FilePicker.pickFiles(type: FileType.any, allowMultiple: false, withReadStream: true);
    if (picked.isEmpty) return;
    setState(() => busy = true);
    try {
      await widget.session.addFileStream(picked.first.name, picked.first.readAsByteStream(), parentId: folderId);
      await _persist();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _dropFiles(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    setState(() => busy = true);
    try {
      for (final file in details.files) {
        await widget.session.addFileStream(file.name, file.openRead(), parentId: folderId);
      }
      await _persist();
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _addFolder() async {
    final name = await _nameDialog('New folder');
    if (name == null) return;
    widget.session.addFolder(name, parentId: folderId);
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _rename(VaultItem item) async {
    final name = await _nameDialog('Rename item', initial: item.name);
    if (name == null) return;
    widget.session.rename(item.id, name);
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _delete(VaultItem item) async {
    await widget.session.delete(item.id);
    await _persist();
    if (mounted) setState(() {});
  }

  Future<void> _export(VaultItem item) async {
    if (item.isDirectory) return;
    final bytes = await widget.session.readFile(item.id);
    final uri = await FilePicker.saveFile(fileName: item.name, bytes: bytes, dialogTitle: 'Export outside the vault');
    if (uri != null && mounted) _message('Exported outside the vault. Other applications can access this file.');
  }

  Future<void> _preview(VaultItem item) async {
    if (item.isDirectory) return;
    final bytes = await widget.session.readFile(item.id);
    final isText = item.name.toLowerCase().endsWith('.txt') || item.name.toLowerCase().endsWith('.json');
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(item.name), content: SizedBox(width: 640, child: isText ? SingleChildScrollView(child: SelectableText(String.fromCharCodes(bytes))) : Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => const Text('Preview is not available for this format.'))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
  }

  Future<void> _share(VaultItem item) async {
    if (item.isDirectory) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Share outside the vault?'), content: const Text('This file will leave the vault and become accessible to other applications.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))]));
    if (confirmed != true) return;
    final bytes = await widget.session.readFile(item.id);
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: item.name)]));
  }

  Future<void> _snapshot() async {
    final name = '${widget.vaultName}.snapshot-${DateTime.now().toIso8601String().replaceAll(':', '-')}.svault';
    final snapshotBytes = Platform.isAndroid ? await widget.session.file.readAsBytes() : Uint8List(0);
    final uri = await FilePicker.saveFile(fileName: name, bytes: snapshotBytes, dialogTitle: 'Save encrypted snapshot');
    if (uri?.scheme == 'file') {
      await widget.session.createSnapshot(File(uri!.toFilePath()));
    }
    if (uri != null && mounted) _message('Encrypted snapshot saved.');
  }

  Future<void> _restoreSnapshot() async {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Choose encrypted snapshot', type: FileType.custom, allowedExtensions: ['svault']);
    if (picked.isEmpty || picked.first.path == null) return;
    final source = picked.first.path!;
    final path = await AndroidStorage.importDocument(source);
    final password = await _nameDialog('Snapshot password', obscure: true);
    if (password == null) return;
    setState(() => busy = true);
    try {
      final restored = await widget.session.restoreSnapshot(File(path), password);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => VaultBrowser(session: restored, vaultName: widget.vaultName, externalUri: widget.externalUri, onSaved: widget.onSaved)));
    } catch (_) {
      if (mounted) _message('Unable to restore snapshot. It may be damaged or use a different password.');
    } finally {
      if (mounted && !widget.session.isLocked) setState(() => busy = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<String?> _nameDialog(String title, {String initial = '', bool obscure = false}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: Text(title), content: TextField(controller: controller, autofocus: true, obscureText: obscure), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save'))]));
    controller.dispose();
    return result?.isEmpty == true ? null : result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropTarget(
      onDragDone: _dropFiles,
      child: Listener(
      onPointerDown: (_) => _armAutoLock(),
      child: Scaffold(
      appBar: AppBar(title: Row(children: [const Icon(Icons.lock_outline, size: 18), const SizedBox(width: 10), Text('${widget.vaultName}.svault')]), actions: [IconButton(onPressed: busy ? null : _importFile, icon: const Icon(Icons.file_upload_outlined), tooltip: 'Import file'), IconButton(onPressed: busy ? null : _addFolder, icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New folder'), IconButton(onPressed: busy ? null : _snapshot, icon: const Icon(Icons.history), tooltip: 'Encrypted snapshot'), IconButton(onPressed: busy ? null : _restoreSnapshot, icon: const Icon(Icons.restore), tooltip: 'Restore snapshot'), IconButton(onPressed: () { widget.session.lock(); Navigator.pop(context); }, icon: const Icon(Icons.lock_outline), tooltip: 'Lock vault')]),
      body: Column(children: [
        if (folderId != null) ListTile(leading: const Icon(Icons.arrow_back), title: const Text('Back'), onTap: () => setState(() => folderId = widget.session.items[folderId]?.parentId)),
        Expanded(child: currentItems.isEmpty ? const Center(child: Text('This folder is empty. Import a file or create a folder.')) : ListView.builder(itemCount: currentItems.length, itemBuilder: (context, index) {
          final item = currentItems[index];
          return ListTile(leading: Icon(item.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined, color: item.isDirectory ? theme.colorScheme.primary : null), title: Text(item.name), subtitle: item.isDirectory ? const Text('Folder') : Text('${item.logicalSize} bytes'), onTap: item.isDirectory ? () => setState(() => folderId = item.id) : () => _preview(item), onLongPress: () => _rename(item), trailing: PopupMenuButton<String>(onSelected: (action) { if (action == 'rename') _rename(item); if (action == 'delete') _delete(item); if (action == 'export') _export(item); if (action == 'share') _share(item); if (action == 'preview') _preview(item); }, itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'preview', child: Text('Preview')), PopupMenuItem(value: 'export', child: Text('Export')), PopupMenuItem(value: 'share', child: Text('Share')), PopupMenuItem(value: 'delete', child: Text('Delete'))]));
        }))]),
      bottomNavigationBar: busy ? const LinearProgressIndicator() : null,
      ),
      ),
    );
  }
}
