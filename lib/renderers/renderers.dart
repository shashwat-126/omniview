import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdfrx/pdfrx.dart';
import '../core/file_detection.dart';
import '../core/limits.dart';
import '../core/office_converter.dart';
import 'api.dart';
import 'spreadsheet_view.dart';
import 'xlsx_parser.dart';

/// Registry: first match wins. Add a renderer here to support a new format.
final List<FileRenderer> renderers = [
  PdfRenderer(), ImageRenderer(), SvgRenderer(), MarkdownRenderer(), CsvRenderer(), SpreadsheetRenderer(),
  ZipRenderer(), NotebookRenderer(), OfficeRenderer(), EncryptedOfficeRenderer(), TextRenderer(), UnsupportedRenderer(),
];

FileRenderer rendererFor(FileKind k) => renderers.firstWhere((r) => r.supports(k));

class _Async<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T) builder;
  const _Async(this.future, this.builder);
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (c, s) => s.hasError
            ? Center(child: Text('Could not open this file:\n${s.error}'))
            : s.hasData
                ? builder(s.data as T)
                : const Center(child: CircularProgressIndicator()),
      );
}

class PdfRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.pdf;
  @override
  Widget build(BuildContext c, OpenedFile f) {
    var attempts = 0;
    // PDFium; pages rendered on demand. Encrypted PDFs: ask for the password (kept in memory only).
    return PdfViewer.data(f.bytes,
        sourceName: f.name, passwordProvider: () => _askPassword(c, attempts++ > 0));
  }
}

Future<String?> _askPassword(BuildContext c, bool retry) {
  if (!c.mounted) return Future.value(null);
  final ctl = TextEditingController();
  return showDialog<String>(
    context: c,
    barrierDismissible: false,
    builder: (d) => AlertDialog(
      title: const Text('Password required'),
      content: TextField(
        controller: ctl,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(labelText: 'PDF password', errorText: retry ? 'Incorrect password' : null),
        onSubmitted: (v) => Navigator.pop(d, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('Open')),
      ],
    ),
  );
}

Uint8List _toPng(Uint8List b) {
  final im = img.decodeImage(b);
  if (im == null) throw 'Unsupported or corrupt image';
  return Uint8List.fromList(img.encodePng(im));
}

const _native = MethodChannel('omniview/image');
// HEIC/HEIF (Android 9+) and AVIF (Android 12+) via the platform ImageDecoder.
Future<Uint8List> _nativePng(Uint8List b) async =>
    (await _native.invokeMethod<Uint8List>('decodeToPng', b))!;

Widget _zoom(Uint8List png) => InteractiveViewer(
    maxScale: 12,
    child: Center(child: Image.memory(png, fit: BoxFit.contain,
        errorBuilder: (_, e, __) => Text('Cannot decode image: $e'))));

class ImageRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.image;
  @override
  Widget build(BuildContext c, OpenedFile f) {
    final ext = f.name.toLowerCase().split('.').last;
    // TIFF/ICO are not decoded by Flutter's engine: decode in Dart (isolate) and show as PNG.
    if ({'heic', 'heif', 'avif'}.contains(ext)) return _Async(_nativePng(f.bytes), _zoom);
    return {'tif', 'tiff', 'ico'}.contains(ext) ? _Async(compute(_toPng, f.bytes), _zoom) : _zoom(f.bytes);
  }
}

/// SVG is drawn by flutter_svg: no scripts run and no remote resources are fetched.
class SvgRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.svg;
  @override
  Widget build(BuildContext c, OpenedFile f) =>
      InteractiveViewer(maxScale: 12, child: Center(child: SvgPicture.memory(f.bytes)));
}

/// Real Excel-style grid. XLSX is parsed directly; XLS/ODS are converted to XLSX by LibreOffice first.
class SpreadsheetRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.xlsx || k == FileKind.convSheet;
  Future<List<SheetData>> _load(OpenedFile f) async {
    var bytes = f.bytes;
    if (f.kind == FileKind.convSheet) {
      bytes = await File(await OfficeConverter.convert(f.name, bytes, 'xlsx')).readAsBytes();
    }
    return compute(parseXlsx, bytes);
  }

  @override
  Widget build(BuildContext c, OpenedFile f) => _Async(_load(f), (List<SheetData> s) => SpreadsheetView(s,
      printView: () async => PdfViewer.file(await OfficeConverter.toPdf(f.name, f.bytes))));
}

class MarkdownRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.markdown;
  @override
  Widget build(BuildContext c, OpenedFile f) => Markdown(
        data: utf8.decode(f.bytes, allowMalformed: true),
        selectable: true,
        // Privacy: never fetch remote images or follow links automatically.
        imageBuilder: (uri, title, alt) => Text('[image blocked: ${alt ?? uri}]'),
        onTapLink: null,
      );
}

List<String> _lines(List<dynamic> a) {
  var s = utf8.decode(a[1] as Uint8List, allowMalformed: true);
  if (a[0] == FileKind.json.index) {
    try {
      s = const JsonEncoder.withIndent('  ').convert(jsonDecode(s));
    } catch (_) {}
  }
  final l = s.split('\n');
  return l.length > Limits.maxTextLines ? l.sublist(0, Limits.maxTextLines) : l;
}

/// Virtualised: only visible lines are built; decoding runs off the UI thread.
class TextRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.text || k == FileKind.json;
  @override
  Widget build(BuildContext c, OpenedFile f) =>
      _Async(compute(_lines, [f.kind.index, f.bytes]), (List<String> lines) {
        const style = TextStyle(fontFamily: 'monospace', fontSize: 13);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 6000,
            child: ListView.builder(
              itemCount: lines.length,
              itemExtent: 20,
              itemBuilder: (_, i) => Row(children: [
                SizedBox(
                    width: 64,
                    child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text('${i + 1}',
                            textAlign: TextAlign.right,
                            style: style.copyWith(color: Colors.grey)))),
                Expanded(child: SelectableText(lines[i], style: style, maxLines: 1)),
              ]),
            ),
          ),
        );
      });
}

List<List<dynamic>> _csv(List<dynamic> a) {
  final text = utf8.decode(a[0] as Uint8List, allowMalformed: true);
  final rows = CsvToListConverter(
          fieldDelimiter: a[1] as String, eol: '\n', shouldParseNumbers: false)
      .convert(text.replaceAll('\r\n', '\n'));
  return rows.length > Limits.maxCsvRows ? rows.sublist(0, Limits.maxCsvRows) : rows;
}

class CsvRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.csv;
  @override
  Widget build(BuildContext c, OpenedFile f) {
    final delim = f.name.toLowerCase().endsWith('.tsv') ? '\t' : ',';
    return _Async(compute(_csv, [f.bytes, delim]), (List<List<dynamic>> rows) {
      final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: cols * 160.0,
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 32,
            itemBuilder: (_, i) => Row(children: [
              for (final cell in rows[i])
                Container(
                  width: 160,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      color: i == 0 ? Colors.black12 : null),
                  child: Text('$cell', overflow: TextOverflow.ellipsis),
                ),
            ]),
          ),
        ),
      );
    });
  }
}

String _unxml(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"').replaceAll('&apos;', "'");

int _num(String path) => int.parse(RegExp(r'\d+').firstMatch(path.split('/').last)!.group(0)!);

String _office(List<dynamic> a) {
  final kind = FileKind.values[a[0] as int];
  final ar = ZipDecoder().decodeBytes(a[1] as Uint8List);
  if (ar.files.length > Limits.maxZipEntries) throw 'Too many entries (zip bomb guard)';
  String read(ArchiveFile f) {
    if (f.size > Limits.maxEntryBytes) throw 'Entry too large: ${f.name}';
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  switch (kind) {
    case FileKind.docx:
      final x = ar.findFile('word/document.xml');
      return x == null
          ? ''
          : _unxml(read(x).replaceAll('</w:p>', '\n').replaceAll('<w:tab/>', '\t'));
    case FileKind.pptx:
      final slides = ar.files
          .where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
          .toList()
        ..sort((p, q) => _num(p.name).compareTo(_num(q.name)));
      return [
        for (var i = 0; i < slides.length; i++)
          '--- Slide ${i + 1} ---\n${_unxml(read(slides[i]).replaceAll('</a:p>', '\n'))}'
      ].join('\n');
    default: // xlsx: shared strings only (grid view is a planned renderer)
      final x = ar.findFile('xl/sharedStrings.xml');
      return x == null ? '' : _unxml(read(x).replaceAll('</si>', '\n'));
  }
}

/// Real rendering: LibreOffice converts to PDF on-device, then PDFium displays it (read-only).
/// If the engine fails on an OOXML file, falls back to an extracted-text preview.
class OfficeRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) =>
      k == FileKind.docx || k == FileKind.pptx || k == FileKind.office;

  Future<Widget> _open(OpenedFile f) async {
    try {
      return PdfViewer.file(await OfficeConverter.toPdf(f.name, f.bytes));
    } catch (e) {
      final panel = Container(
        width: double.infinity,
        color: Colors.red.shade900,
        padding: const EdgeInsets.all(12),
        child: SelectableText(
            e is UnsupportedError
                ? 'LITE BUILD: this version of OmniView does not include the Office rendering engine, so this is not '
                    'a real preview. Install the full build for pages that look like Word/PowerPoint.'
                : 'REAL RENDERING FAILED. What follows is NOT how this file looks in Word/PowerPoint.\n\n'
                    '$e\n\n${await OfficeConverter.diagnose()}\n\n'
                    'If this file is password-protected, remove the password first: the engine cannot open it.',
            style: const TextStyle(color: Colors.white)),
      );
      if (f.kind == FileKind.office) return panel; // no text fallback for legacy/ODF
      return Column(children: [panel, Expanded(child: _textPreview(f, 'Extracted text only:'))]);
    }
  }

  Widget _textPreview(OpenedFile f, String note) => Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Text(note)),
        Expanded(
            child: _Async(
                compute(_office, [f.kind.index, f.bytes]),
                (String t) => SingleChildScrollView(
                    padding: const EdgeInsets.all(16), child: SelectableText(t)))),
      ]);

  @override
  Widget build(BuildContext c, OpenedFile f) => _Async<Widget>(_open(f), (w) => w);
}

Map<String, dynamic> _nbParse(Uint8List b) =>
    jsonDecode(utf8.decode(b, allowMalformed: true)) as Map<String, dynamic>;
String _j(dynamic s, [String sep = '']) => s is List ? s.join(sep) : '${s ?? ''}';
final _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

/// Jupyter-style read-only notebook: rendered Markdown cells, code cells with execution counts,
/// and outputs (streams, text results, inline PNG/JPEG images, error tracebacks).
class NotebookRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.notebook;

  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5);

  Widget _out(Map o) {
    Widget mono(String t, {Color? color}) => Padding(
        padding: const EdgeInsets.only(left: 64, top: 4),
        child: SelectableText(t, style: _mono.copyWith(color: color)));
    switch (o['output_type']) {
      case 'stream':
        return mono(_j(o['text']));
      case 'error':
        return mono(_j(o['traceback'], '\n').replaceAll(_ansi, ''), color: Colors.red);
      default:
        final d = (o['data'] as Map?) ?? {};
        final png = d['image/png'] ?? d['image/jpeg'];
        if (png != null) {
          return Padding(
              padding: const EdgeInsets.only(left: 64, top: 4),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.memory(base64Decode(_j(png).replaceAll(RegExp(r'\s'), '')),
                      errorBuilder: (_, e, __) => const Text('[image could not be decoded]'))));
        }
        return d['text/plain'] != null ? mono(_j(d['text/plain'])) : const SizedBox.shrink();
    }
  }

  Widget _cell(Map cell) {
    final src = _j(cell['source']);
    if (cell['cell_type'] == 'markdown') {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: MarkdownBody(
              data: src, selectable: true,
              imageBuilder: (u, t, a) => Text('[image blocked: ${a ?? u}]')));
    }
    if (cell['cell_type'] != 'code') return SelectableText(src);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 64, child: Text('[${cell['execution_count'] ?? ' '}]:',
              style: _mono.copyWith(color: Colors.indigo))),
          Expanded(child: Container(
              width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.black12,
              child: SelectableText(src, style: _mono))),
        ]),
        for (final o in (cell['outputs'] as List?) ?? const []) _out(o as Map),
      ]),
    );
  }

  @override
  Widget build(BuildContext c, OpenedFile f) => _Async(compute(_nbParse, f.bytes), (Map<String, dynamic> nb) {
        final cells = (nb['cells'] as List?) ?? const [];
        return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: cells.length,
            itemBuilder: (_, i) => _cell(cells[i] as Map));
      });
}

class ZipRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.zip;
  @override
  Widget build(BuildContext c, OpenedFile f) {
    final ar = ZipDecoder().decodeBytes(f.bytes); // listing only; nothing is extracted
    if (ar.files.length > Limits.maxZipEntries) {
      return const Center(child: Text('Archive has too many entries.'));
    }
    return ListView.builder(
      itemCount: ar.files.length,
      itemBuilder: (_, i) => ListTile(
        dense: true,
        leading: Icon(ar.files[i].isFile ? Icons.insert_drive_file : Icons.folder),
        title: Text(ar.files[i].name),
        subtitle: Text('${ar.files[i].size} bytes'),
      ),
    );
  }
}

/// Password-protected Office files cannot be opened offline yet; say so clearly.
class EncryptedOfficeRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => k == FileKind.encrypted;
  @override
  Widget build(BuildContext c, OpenedFile f) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(f.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'This Office file is password-protected. OmniView cannot decrypt Office files yet.\n\n'
                'Open it in Word/Excel/PowerPoint, remove the password, and save a copy to view it here.',
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

class UnsupportedRenderer implements FileRenderer {
  @override
  bool supports(FileKind k) => true;
  @override
  Widget build(BuildContext c, OpenedFile f) => Center(
      child: Text('${f.name}\nThis format is not supported yet.', textAlign: TextAlign.center));
}
