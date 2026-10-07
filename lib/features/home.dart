import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_state.dart';
import '../core/file_detection.dart';
import '../core/limits.dart';
import '../shared/file_style.dart';
import 'about_page.dart';
import 'viewer_page.dart';

String _base(String p) => p.split(RegExp(r'[\\/]')).last;

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  static const _formats = [
    'PDF', 'Word', 'Excel', 'PowerPoint', 'OpenDocument', 'Images', 'Markdown', 'Code', 'Notebooks', 'CSV', 'ZIP'
  ];

  void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

  /// Shows a spinner while the file is read (large files can take a moment).
  Future<Uint8List?> _read(BuildContext c, Future<Uint8List> Function() job) async {
    showDialog<void>(
        context: c, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      return await job();
    } catch (_) {
      if (c.mounted) _snack(c, 'Could not read that file.');
      return null;
    } finally {
      if (c.mounted) Navigator.of(c).pop();
    }
  }

  Future<void> _open(BuildContext c, WidgetRef ref, String name, Uint8List bytes, String? path) async {
    if (bytes.length > Limits.maxFileBytes) {
      _snack(c, 'File too large (limit 200 MB).');
      return;
    }
    if (path != null) {
      await addRecent(path);
      ref.invalidate(recentsProvider);
    }
    if (!c.mounted) return;
    final kind = detectKind(name, bytes.sublist(0, bytes.length < 512 ? bytes.length : 512));
    await Navigator.push(c, MaterialPageRoute(builder: (_) => ViewerPage(name: name, bytes: bytes, kind: kind)));
  }

  Future<void> _pick(BuildContext c, WidgetRef ref) async {
    final f = await FilePicker.pickFile();
    if (f == null || !c.mounted) return;
    final bytes = await _read(c, () => f.readAsBytes());
    if (bytes == null || !c.mounted) return;
    await _open(c, ref, f.name, bytes, kIsWeb ? null : f.path);
  }

  Widget _hero(BuildContext c, WidgetRef ref) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Open anything.',
              style: Theme.of(c).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Documents, spreadsheets, slides, images and code, rendered right on your device.',
              style: TextStyle(color: Colors.white70, height: 1.35)),
          const SizedBox(height: 16),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in _formats)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                child: Text(f, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF4F46E5)),
              onPressed: () => _pick(c, ref),
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose a file'),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.shield_outlined, color: Colors.white70, size: 18),
            const SizedBox(width: 6),
            const Flexible(
                child: Text('Offline · No tracking', style: TextStyle(color: Colors.white70, fontSize: 12))),
          ]),
        ]),
      );

  Widget _recentTile(BuildContext c, WidgetRef ref, String path) {
    final name = _base(path), st = styleForName(name), cs = Theme.of(c).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: st.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(st.icon, color: st.color),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(st.label),
        trailing: IconButton(
          tooltip: 'Remove from recents',
          icon: const Icon(Icons.close, size: 18),
          onPressed: () async {
            await removeRecent(path);
            ref.invalidate(recentsProvider);
          },
        ),
        onTap: () async {
          final b = await _read(c, () => XFile(path).readAsBytes());
          if (b == null || !c.mounted) return;
          await _open(c, ref, name, b, path);
        },
      ),
    );
  }

  Widget _empty(BuildContext c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(children: [
          Icon(Icons.history, size: 40, color: Theme.of(c).colorScheme.outline),
          const SizedBox(height: 10),
          const Text('No recent files yet', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Files you open appear here. Only the file path is remembered, never the content.',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.outline)),
        ]),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/icon/icon.png', width: 30, height: 30)),
          const SizedBox(width: 10),
          const Text('OmniView', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        actions: [
          IconButton(
            tooltip: 'About & settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            _hero(context, ref),
            const SizedBox(height: 24),
            Row(children: [
              Text('Recent files', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if ((recents.value ?? const []).isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await clearRecents();
                    ref.invalidate(recentsProvider);
                  },
                  child: const Text('Clear'),
                ),
            ]),
            const SizedBox(height: 8),
            recents.when(
              data: (l) => l.isEmpty ? _empty(context) : Column(children: [for (final p in l) _recentTile(context, ref, p)]),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('$e'),
            ),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pick(context, ref),
        icon: const Icon(Icons.folder_open),
        label: const Text('Open file'),
      ),
    );
  }
}
