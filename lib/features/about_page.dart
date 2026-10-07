import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_state.dart';
import '../core/office_converter.dart';

const _repo = 'https://github.com/shashwat-126/omniview';
const _version = '0.1.0';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  Widget _section(BuildContext c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(t, style: Theme.of(c).textTheme.titleSmall?.copyWith(color: Theme.of(c).colorScheme.primary)),
      );

  Widget _point(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_circle_outline, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(t)),
        ]),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('About & settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Row(children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset('assets/icon/icon.png', width: 64, height: 64)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('OmniView', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Text('Version $_version  ·  Private, offline file viewer'),
                ]),
              ),
            ]),
            _section(context, 'APPEARANCE'),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {mode},
              onSelectionChanged: (s) {
                ref.read(themeModeProvider.notifier).state = s.first;
                saveThemeMode(s.first);
              },
            ),
            _section(context, 'PRIVACY'),
            _point('No account, no analytics, no ads, no tracking.'),
            _point('Files are opened and rendered on your device. OmniView itself makes no network requests.'),
            _point('Recent files store only the file path, never the content. Previews are cached privately and can be cleared.'),
            _point('Opened files are read-only: OmniView never modifies your documents.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear recent files and cached previews'),
              onPressed: () async {
                await clearRecents();
                try {
                  await OfficeConverter.clearCache();
                } catch (_) {}
                ref.invalidate(recentsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History and cache cleared.')));
                }
              },
            ),
            _section(context, 'SUPPORTED FORMATS'),
            const Text(
                'PDF · Word (DOC, DOCX, ODT, RTF) · Excel (XLS, XLSX, ODS, CSV, TSV) · PowerPoint (PPT, PPTX, ODP) · '
                'Images (JPG, PNG, WEBP, GIF, BMP, TIFF, ICO, SVG, HEIC/AVIF on supported Android) · Markdown · '
                'Jupyter notebooks · Code and text files · ZIP archives.'),
            _section(context, 'ABOUT'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code),
              title: const Text('Source code'),
              subtitle: const SelectableText(_repo),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Open-source licenses'),
              onTap: () => showLicensePage(
                  context: context, applicationName: 'OmniView', applicationVersion: _version),
            ),
          ]),
        ),
      ),
    );
  }
}
