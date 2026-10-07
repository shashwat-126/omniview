import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:libre_office_kit_converter_plugin/libre_office_kit_converter_plugin.dart';
import 'package:path_provider/path_provider.dart';

/// Read-only Office/ODF rendering: LibreOffice (on-device, offline) converts the document to a
/// PDF in app-private cache, and the PDF viewer displays it. Nothing leaves the device.
class OfficeConverter {
  // ADJUST: confirm the class name/constructor in the plugin's "Example" tab on pub.dev.
  static final _lok = LibreOfficeKitConverterPlugin();
  static Future<void>? _init;
  static Future<void> _tail = Future.value();
  static const _maxCached = 20;
  static const _timeout = Duration(seconds: 90);

  /// Call early (from main, unawaited) so the engine's slow first start is hidden.
  static Future<void> warmUp() =>
      _init ??= Platform.isAndroid ? _lok.init().then((_) {}) : Future<void>.value();

  /// LibreOfficeKit converts one document at a time, so jobs are queued explicitly.
  static Future<T> _serial<T>(Future<T> Function() job) {
    final r = _tail.then((_) => job());
    _tail = r.then((_) {}, onError: (_) {});
    return r;
  }

  static Future<Directory> _dir() async {
    // Android: app-private cache. Desktop (dev): a visible folder in $HOME, because snap-packaged
    // LibreOffice cannot read hidden directories such as ~/.cache.
    final base = Platform.isAndroid
        ? await getApplicationCacheDirectory()
        : Directory(Platform.environment['HOME'] ?? Directory.systemTemp.path);
    final name = Platform.isAndroid ? 'office_cache' : 'omniview_preview_cache';
    return Directory('${base.path}/$name').create(recursive: true);
  }

  static Future<String> toPdf(String name, Uint8List bytes) => convert(name, bytes, 'pdf');

  /// format: 'pdf' for documents/slides, 'xlsx' to read legacy XLS/ODS as a real grid.
  static Future<String> convert(String name, Uint8List bytes, String format) async {
    final dir = await _dir();
    final key = sha256.convert(bytes).toString().substring(0, 32);
    final out = File('${dir.path}/$key.$format');
    if (await out.exists()) {
      await out.setLastModified(DateTime.now()); // LRU touch
      return out.path;
    }
    return _serial(() async {
      await warmUp();
      final ext = name.contains('.') ? name.split('.').last.replaceAll(RegExp(r'[^A-Za-z0-9]'), '') : 'bin';
      final input = File('${dir.path}/$key.$ext');
      try {
        await input.writeAsBytes(bytes, flush: true);
        // Android: on-device LibreOfficeKit. Desktop (development only): local `soffice` CLI.
        final path = Platform.isAndroid
            ? await _lok
                .convert(filePath: input.path, outputFormat: format, outputFilePath: out.path)
                .timeout(_timeout)
            : await _viaSoffice(input, dir, format, out);
        if (path == null || !await File(path).exists()) throw 'Conversion produced no output';
        await _evict(dir);
        return path;
      } finally {
        if (await input.exists()) await input.delete(); // never keep a copy of the source
      }
    });
  }

  static List<String>? _cmd;

  /// Finds a working LibreOffice launcher: PATH, apt, snap, flatpak, /opt installs, or
  /// OMNIVIEW_SOFFICE=/path/to/soffice. Each entry is [executable, ...leading args].
  static Future<List<String>> _findSoffice() async {
    if (_cmd != null) return _cmd!;
    final home = Platform.environment['HOME'] ?? '';
    final env = Platform.environment['OMNIVIEW_SOFFICE'];
    final cands = <List<String>>[
      if (env != null && env.isNotEmpty) [env],
      ['soffice'], ['libreoffice'], ['/usr/bin/soffice'], ['/usr/bin/libreoffice'],
      ['/usr/lib/libreoffice/program/soffice'], ['/usr/local/bin/soffice'],
      ['/snap/bin/libreoffice'], ['/snap/bin/libreoffice.soffice'],
      ['/var/lib/flatpak/exports/bin/org.libreoffice.LibreOffice'],
      ['$home/.local/share/flatpak/exports/bin/org.libreoffice.LibreOffice'],
      ['flatpak', 'run', '--command=soffice', 'org.libreoffice.LibreOffice'],
    ];
    try {
      for (final d in Directory('/opt').listSync()) {
        if (d.path.split('/').last.toLowerCase().startsWith('libreoffice')) {
          cands.add(['${d.path}/program/soffice']);
        }
      }
    } catch (_) {}
    for (final c in cands) {
      try {
        final r = await Process.run(c.first, [...c.skip(1), '--version']).timeout(const Duration(seconds: 90));
        if (r.exitCode == 0) return _cmd = c;
      } catch (_) {}
    }
    throw 'LibreOffice not found. Tried: ${cands.map((c) => c.join(' ')).join(', ')}';
  }

  /// Human-readable engine check shown when rendering fails.
  static Future<String> diagnose() async {
    if (Platform.isAndroid) return 'Engine: LibreOfficeKit plugin (Android).';
    try {
      final c = await _findSoffice();
      final r = await Process.run(c.first, [...c.skip(1), '--version']).timeout(const Duration(seconds: 90));
      return 'Using ${c.join(' ')}: ${r.stdout}'.trim();
    } catch (_) {
      return 'Fix: install LibreOffice (sudo apt install libreoffice-writer libreoffice-calc libreoffice-impress),\n'
          'or point to it: OMNIVIEW_SOFFICE=/full/path/to/soffice flutter run\n'
          'Word-like fonts: sudo apt install fonts-crosextra-carlito fonts-crosextra-caladea';
    }
  }

  /// Desktop dev fallback: needs LibreOffice installed (e.g. `sudo apt install libreoffice`).
  /// Uses an isolated profile so it works while LibreOffice is open. Output name == `out`.
  static Future<String> _viaSoffice(File input, Directory dir, String format, File out) async {
    final profile = Directory('${dir.path}/lo_profile');
    final cmd = await _findSoffice();
    final r = await Process.run(cmd.first, [
      ...cmd.skip(1),
      '--headless', '--norestore', '-env:UserInstallation=file://${profile.path}',
      '--convert-to', format, '--outdir', dir.path, input.path,
    ]).timeout(_timeout);
    if (r.exitCode != 0 || !await out.exists()) {
      throw 'LibreOffice conversion failed (exit ${r.exitCode}): ${r.stderr}';
    }
    return out.path;
  }

  static Future<void> _evict(Directory dir) async {
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf') || f.path.endsWith('.xlsx')).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final f in files.skip(_maxCached)) {
      await f.delete();
    }
  }

  /// Wired to the "Clear history" button: deletes every rendered preview.
  static Future<void> clearCache() async {
    final d = await _dir();
    if (await d.exists()) await d.delete(recursive: true);
  }
}
