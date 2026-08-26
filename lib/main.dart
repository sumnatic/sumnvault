import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sumnvault/core/vault/vault_engine.dart';

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
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> _createVault() async {
    final details = await _passwordDialog('Create a vault');
    if (details == null || !mounted) return;
    final uri = await FilePicker.saveFile(dialogTitle: 'Choose vault location', fileName: '${details.$1}.svault', bytes: Uint8List(0), type: FileType.custom, allowedExtensions: ['svault']);
    final path = uri?.scheme == 'file' ? uri!.toFilePath() : uri?.path;
    if (path == null || !mounted) return;
    await engine.create(File(path), details.$2);
    setState(() => vaults.insert(0, VaultData('${details.$1}.svault', 'Opened just now', '0 B', Icons.lock_outline, const Color(0xffd891ff))));
    _message('Vault created and encrypted locally.');
  }

  Future<void> _openVault() async {
    // file_picker 12 does not expose pickFile yet; select one entry from the list API.
    // ignore: deprecated_member_use
    final picked = await FilePicker.pickFiles(dialogTitle: 'Open SumnVault', type: FileType.custom, allowedExtensions: ['svault'], allowMultiple: false);
    final path = picked.isNotEmpty ? picked.first.path : null;
    if (path == null || !mounted) return;
    final password = await _passwordDialog('Unlock vault', nameOnly: true);
    if (password == null || !mounted) return;
    try {
      final opened = await engine.open(File(path), password.$2);
      await opened.verify();
      _message('Vault unlocked and integrity verified.');
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
      SliverPadding(padding: EdgeInsets.fromLTRB(side, 14, side, 48), sliver: SliverGrid(delegate: SliverChildBuilderDelegate((context, index) => VaultCard(vault: filtered[index]), childCount: filtered.length), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 360, mainAxisExtent: 205, crossAxisSpacing: 16, mainAxisSpacing: 16))),
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
}

class VaultData {
  const VaultData(this.name, this.lastOpened, this.size, this.icon, this.color);
  final String name;
  final String lastOpened;
  final String size;
  final IconData icon;
  final Color color;
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
  const VaultCard({super.key, required this.vault});
  final VaultData vault;
  @override
  Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlock flow is ready for the vault engine.'))), child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: vault.color.withValues(alpha: .14), borderRadius: BorderRadius.circular(11)), child: Icon(vault.icon, color: vault.color)), const Spacer(), const Icon(Icons.lock_outline, size: 18)]),
        const Spacer(),
        Text(vault.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(children: [Expanded(child: Text(vault.lastOpened, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)), const SizedBox(width: 8), Text(vault.size, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))]),
      ]))));
}
