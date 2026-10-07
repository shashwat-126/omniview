import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../core/limits.dart';

class XfStyle {
  final bool bold, italic, underline, wrap;
  final int? color, fill; // ARGB
  final String? align;
  final double? size;
  const XfStyle({this.bold = false, this.italic = false, this.underline = false, this.wrap = false,
      this.color, this.fill, this.align, this.size});
}

class Merge {
  final int r1, c1, r2, c2; // 0-based, inclusive
  const Merge(this.r1, this.c1, this.r2, this.c2);
}

class SheetData {
  final String name;
  final List<List<String>> rows;
  final List<List<int>> xf; // per-cell index into palette
  final List<XfStyle> palette;
  final List<Merge> merges;
  final Map<int, double> colPx, rowPx; // explicit sizes in px (0 = hidden)
  final double defCol, defRow;
  final int freezeRows, freezeCols;
  SheetData(this.name, this.rows,
      {this.xf = const [], this.palette = const [XfStyle()], this.merges = const [],
      this.colPx = const {}, this.rowPx = const {}, this.defCol = 64, this.defRow = 20,
      this.freezeRows = 0, this.freezeCols = 0});
  int get cols => rows.fold(0, (m, r) => r.length > m ? r.length : m);
}

const _dateIds = {14, 15, 16, 17, 22};
const _timeIds = {18, 19, 20, 21, 45, 46, 47};
const _builtin = {1: '0', 2: '0.00', 3: '#,##0', 4: '#,##0.00'};
String _p(int n) => n.toString().padLeft(2, '0');

int _col(String ref) {
  var n = 0;
  for (final u in ref.codeUnits) {
    if (u >= 65 && u <= 90) { n = n * 26 + (u - 64); } else if (u >= 97 && u <= 122) { n = n * 26 + (u - 96); } else { break; }
  }
  return n - 1;
}

String _number(double v, int id, String? code) {
  var hasDate = _dateIds.contains(id), hasTime = _timeIds.contains(id);
  if (code != null && !hasDate && !hasTime) {
    final c = code.replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '').toLowerCase();
    hasDate = RegExp(r'[yd]').hasMatch(c);
    hasTime = RegExp(r'[hs]').hasMatch(c);
  }
  if (hasDate || hasTime) {
    final d = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: (v * 86400000).round()));
    final date = '${d.year}-${_p(d.month)}-${_p(d.day)}', time = '${_p(d.hour)}:${_p(d.minute)}:${_p(d.second)}';
    return hasDate && hasTime ? '$date ${time.substring(0, 5)}' : hasDate ? date : time;
  }
  final f = code ?? _builtin[id] ?? (id == 9 ? '0%' : id == 10 ? '0.00%' : null);
  if (f != null && RegExp(r'[0#]').hasMatch(f)) {
    final pct = f.contains('%');
    final dec = RegExp(r'\.([0#]+)').firstMatch(f)?.group(1)!.length ?? 0;
    final parts = (pct ? v * 100 : v).toStringAsFixed(dec).split('.');
    if (f.contains(',')) {
      parts[0] = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    }
    return parts.join('.') + (pct ? '%' : '');
  }
  return v == v.truncateToDouble() && v.abs() < 1e15
      ? v.toInt().toString()
      : double.parse(v.toStringAsPrecision(15)).toString();
}

const _theme = [0xFFFFFF, 0x000000, 0xE7E6E6, 0x44546A, 0x4472C4, 0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47];
const _indexed = {8: 0x000000, 9: 0xFFFFFF, 10: 0xFF0000, 11: 0x00FF00, 12: 0x0000FF, 13: 0xFFFF00, 14: 0xFF00FF, 15: 0x00FFFF};

int? _color(XmlElement? e) {
  if (e == null) return null;
  int? rgb;
  final a = e.getAttribute('rgb');
  if (a != null && a.length >= 6) rgb = int.tryParse(a.substring(a.length - 6), radix: 16);
  final t = int.tryParse(e.getAttribute('theme') ?? '');
  if (rgb == null && t != null && t < _theme.length) rgb = _theme[t];
  final i = int.tryParse(e.getAttribute('indexed') ?? '');
  if (rgb == null && i != null) rgb = _indexed[i];
  if (rgb == null) return null;
  final tint = double.tryParse(e.getAttribute('tint') ?? '') ?? 0;
  int ch(int v) => (tint > 0 ? v + (255 - v) * tint : v * (1 + tint)).round().clamp(0, 255).toInt();
  return 0xFF000000 | (ch((rgb >> 16) & 255) << 16) | (ch((rgb >> 8) & 255) << 8) | ch(rgb & 255);
}

int _row(String ref) => (int.tryParse(ref.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1) - 1;

/// Runs in an isolate. Reads cached values, number formats, fonts, fills, alignment, merged cells,
/// column widths, row heights, hidden rows/columns and frozen panes. Legacy XLS/ODS are converted
/// to XLSX by LibreOffice first, which stores computed values.
List<SheetData> parseXlsx(Uint8List bytes) {
  final ar = ZipDecoder().decodeBytes(bytes);
  if (ar.files.length > Limits.maxZipEntries) throw 'Too many entries (zip bomb guard)';
  String? text(String n) {
    final f = ar.findFile(n);
    if (f == null) return null;
    if (f.size > Limits.maxEntryBytes) throw 'Entry too large: $n';
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final shared = <String>[];
  final ss = text('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  final fmts = <int, String>{};
  final xfFmt = <int>[];
  final palette = <XfStyle>[];
  final st = text('xl/styles.xml');
  if (st != null) {
    final d = XmlDocument.parse(st);
    for (final n in d.findAllElements('numFmt')) {
      fmts[int.parse(n.getAttribute('numFmtId')!)] = n.getAttribute('formatCode') ?? '';
    }
    final fonts = [for (final f in d.findAllElements('fonts')) ...f.findElements('font')];
    final fills = [for (final f in d.findAllElements('fills')) ...f.findElements('fill')];
    bool flag(XmlElement? e) => e != null && !['0', 'false'].contains(e.getAttribute('val'));
    for (final cx in d.findAllElements('cellXfs')) {
      for (final x in cx.findElements('xf')) {
        final fo = int.tryParse(x.getAttribute('fontId') ?? '') ?? 0;
        final fi = int.tryParse(x.getAttribute('fillId') ?? '') ?? 0;
        final font = fo < fonts.length ? fonts[fo] : null;
        final pf = fi < fills.length ? fills[fi].getElement('patternFill') : null;
        final al = x.getElement('alignment');
        xfFmt.add(int.tryParse(x.getAttribute('numFmtId') ?? '0') ?? 0);
        palette.add(XfStyle(
          bold: flag(font?.getElement('b')),
          italic: flag(font?.getElement('i')),
          underline: font?.getElement('u') != null,
          color: _color(font?.getElement('color')),
          size: double.tryParse(font?.getElement('sz')?.getAttribute('val') ?? ''),
          fill: pf?.getAttribute('patternType') == 'solid' ? _color(pf?.getElement('fgColor')) : null,
          align: al?.getAttribute('horizontal'),
          wrap: ['1', 'true'].contains(al?.getAttribute('wrapText')),
        ));
      }
    }
  }
  if (palette.isEmpty) palette.add(const XfStyle());
  final rels = <String, String>{};
  for (final r in XmlDocument.parse(text('xl/_rels/workbook.xml.rels')!).findAllElements('Relationship')) {
    rels[r.getAttribute('Id')!] = r.getAttribute('Target')!;
  }
  String value(XmlElement c) {
    final t = c.getAttribute('t');
    if (t == 'inlineStr') return c.findAllElements('t').map((e) => e.innerText).join();
    final v = c.getElement('v')?.innerText;
    if (v == null || v.isEmpty) return '';
    switch (t) {
      case 's':
        final i = int.tryParse(v);
        return i != null && i < shared.length ? shared[i] : '';
      case 'b':
        return v == '1' ? 'TRUE' : 'FALSE';
      case 'str':
      case 'e':
        return v;
      default:
        final d = double.tryParse(v);
        if (d == null) return v;
        final si = int.tryParse(c.getAttribute('s') ?? '');
        final id = si != null && si < xfFmt.length ? xfFmt[si] : 0;
        return _number(d, id, fmts[id]);
    }
  }

  final out = <SheetData>[];
  for (final s in XmlDocument.parse(text('xl/workbook.xml')!).findAllElements('sheet')) {
    final rid = s.attributes.firstWhere((a) => a.name.local == 'id').value;
    var target = rels[rid]!;
    target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final xml = text(target);
    final rows = <List<String>>[], xfRows = <List<int>>[], merges = <Merge>[];
    final colPx = <int, double>{}, rowPx = <int, double>{};
    var defCol = 64.0, defRow = 20.0, fr = 0, fc = 0;
    if (xml != null) {
      final doc = XmlDocument.parse(xml);
      final fp = doc.findAllElements('sheetFormatPr');
      if (fp.isNotEmpty) {
        final w = double.tryParse(fp.first.getAttribute('defaultColWidth') ?? '');
        if (w != null) defCol = w * 7 + 5;
        final h = double.tryParse(fp.first.getAttribute('defaultRowHeight') ?? '');
        if (h != null) defRow = h * 4 / 3;
      }
      for (final pane in doc.findAllElements('pane')) {
        if ((pane.getAttribute('state') ?? '').startsWith('frozen')) {
          fc = int.tryParse(pane.getAttribute('xSplit') ?? '') ?? 0;
          fr = int.tryParse(pane.getAttribute('ySplit') ?? '') ?? 0;
        }
        break;
      }
      for (final c in doc.findAllElements('col')) {
        final lo = int.tryParse(c.getAttribute('min') ?? '') ?? 1, hi = int.tryParse(c.getAttribute('max') ?? '') ?? lo;
        final w = double.tryParse(c.getAttribute('width') ?? '');
        final hidden = c.getAttribute('hidden') == '1';
        if (w == null && !hidden) continue;
        for (var i = lo - 1; i <= hi - 1 && i < 2000; i++) { colPx[i] = hidden ? 0 : w! * 7 + 5; }
      }
      var rc = 0;
      for (final row in doc.findAllElements('row')) {
        final ri = (int.tryParse(row.getAttribute('r') ?? '') ?? rc + 1) - 1;
        rc = ri + 1;
        if (ri >= Limits.maxCsvRows) break;
        while (rows.length <= ri) { rows.add(<String>[]); xfRows.add(<int>[]); }
        final ht = double.tryParse(row.getAttribute('ht') ?? '');
        if (row.getAttribute('hidden') == '1') { rowPx[ri] = 0; } else if (ht != null) { rowPx[ri] = ht * 4 / 3; }
        final line = rows[ri], xl = xfRows[ri];
        var ci = 0;
        for (final c in row.findElements('c')) {
          final ref = c.getAttribute('r');
          final col = ref == null ? ci : _col(ref);
          ci = col + 1;
          if (col < 0 || col >= 2000) continue;
          while (line.length <= col) { line.add(''); }
          while (xl.length <= col) { xl.add(0); }
          line[col] = value(c);
          xl[col] = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
        }
      }
      for (final m in doc.findAllElements('mergeCell')) {
        final parts = (m.getAttribute('ref') ?? '').split(':');
        if (parts.length == 2) {
          final c1 = _col(parts[0]), c2 = _col(parts[1]), r1 = _row(parts[0]), r2 = _row(parts[1]);
          if (c2 < 2000 && r2 < Limits.maxCsvRows) merges.add(Merge(r1, c1, r2, c2));
        }
      }
    }
    out.add(SheetData(s.getAttribute('name') ?? 'Sheet', rows,
        xf: xfRows, palette: palette, merges: merges, colPx: colPx, rowPx: rowPx,
        defCol: defCol, defRow: defRow, freezeRows: fr, freezeCols: fc));
  }
  return out;
}
