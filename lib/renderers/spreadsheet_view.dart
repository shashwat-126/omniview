import 'package:flutter/material.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'xlsx_parser.dart';

const _gridLine = Color(0xFFD4D4D4);

/// Excel-style read-only view: styled cells (fonts, fills, alignment), merged cells, frozen panes,
/// real column widths / row heights, zoom, sheet tabs, and a "Print layout" mode (LibreOffice -> PDF)
/// that shows charts and page breaks.
class SpreadsheetView extends StatefulWidget {
  final List<SheetData> sheets;
  final Future<Widget> Function() printView;
  const SpreadsheetView(this.sheets, {required this.printView, super.key});
  @override
  State<SpreadsheetView> createState() => _State();
}

class _State extends State<SpreadsheetView> {
  int _i = 0;
  double _zoom = 1;
  bool _print = false;
  Future<Widget>? _printFuture;
  final _merge = <SheetData, Map<int, Merge>>{};

  String _letters(int n) {
    var s = '';
    n++;
    while (n > 0) {
      s = String.fromCharCode(65 + (n - 1) % 26) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  /// Covered-cell lookup. Merges crossing the frozen boundary or larger than 5000 cells are skipped
  /// (TableView cannot merge across pinned/unpinned regions).
  Map<int, Merge> _mergeIndex(SheetData s) => _merge[s] ??= () {
        final m = <int, Merge>{};
        for (final g in s.merges) {
          if ((g.r2 - g.r1 + 1) * (g.c2 - g.c1 + 1) > 5000) continue;
          if ((g.r1 < s.freezeRows && g.r2 >= s.freezeRows) || (g.c1 < s.freezeCols && g.c2 >= s.freezeCols)) continue;
          for (var r = g.r1; r <= g.r2; r++) {
            for (var c = g.c1; c <= g.c2; c++) { m[r * 4096 + c] = g; }
          }
        }
        return m;
      }();

  /// Excel auto-fits rows without an explicit height to the largest font in the row.
  double _rowH(SheetData s, int r) {
    final e = s.rowPx[r];
    if (e != null) return e;
    var mx = 11.0;
    if (r < s.xf.length) {
      for (final x in s.xf[r]) {
        final sz = x < s.palette.length ? s.palette[x].size : null;
        if (sz != null && sz > mx) mx = sz;
      }
    }
    return mx > 11 ? mx * 1.82 : s.defRow;
  }

  Widget _head(String t, double z) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFFF3F3F3), border: Border.all(color: _gridLine, width: 0.5)),
        child: Text(t, style: TextStyle(fontSize: 12 * z, color: const Color(0xFF555555))),
      );

  Widget _data(String t, XfStyle st, double z) {
    final numeric = RegExp(r'^-?[\d,]*\.?\d+%?$|^\d{4}-\d\d-\d\d').hasMatch(t);
    final al = switch (st.align) {
      'center' || 'centerContinuous' => Alignment.center,
      'right' => Alignment.centerRight,
      'left' => Alignment.centerLeft,
      _ => numeric ? Alignment.centerRight : Alignment.centerLeft,
    };
    return Container(
      alignment: al,
      padding: EdgeInsets.symmetric(horizontal: 4 * z),
      decoration: BoxDecoration(
          color: st.fill != null ? Color(st.fill!) : Colors.white,
          border: Border.all(color: _gridLine, width: 0.5)),
      child: Text(t,
          maxLines: st.wrap ? null : 1,
          softWrap: st.wrap,
          overflow: st.wrap ? TextOverflow.clip : TextOverflow.ellipsis,
          style: TextStyle(
            color: Color(st.color ?? 0xFF000000),
            fontSize: (st.size ?? 11) * 1.25 * z,
            fontWeight: st.bold ? FontWeight.bold : null,
            fontStyle: st.italic ? FontStyle.italic : null,
            decoration: st.underline ? TextDecoration.underline : null,
          )),
    );
  }

  Widget _grid(SheetData s) {
    final z = _zoom, merges = _mergeIndex(s);
    return Container(
      color: Colors.white,
      child: TableView.builder(
        key: ValueKey('$_i-$_zoom'),
        rowCount: s.rows.length + 1,
        columnCount: (s.cols < 1 ? 1 : s.cols) + 1,
        pinnedRowCount: 1 + s.freezeRows,
        pinnedColumnCount: 1 + s.freezeCols,
        columnBuilder: (t) => TableSpan(
            extent: FixedTableSpanExtent((t == 0 ? 48 : (s.colPx[t - 1] ?? s.defCol)) * z)),
        rowBuilder: (t) => TableSpan(
            extent: FixedTableSpanExtent((t == 0 ? 22 : _rowH(s, t - 1)) * z)),
        cellBuilder: (ctx, v) {
          final tr = v.row, tc = v.column;
          if (tr == 0 && tc == 0) return TableViewCell(child: _head('', z));
          if (tr == 0) return TableViewCell(child: _head(_letters(tc - 1), z));
          if (tc == 0) return TableViewCell(child: _head('$tr', z));
          final r = tr - 1, c = tc - 1, m = merges[r * 4096 + c];
          final or = m?.r1 ?? r, oc = m?.c1 ?? c;
          final text = or < s.rows.length && oc < s.rows[or].length ? s.rows[or][oc] : '';
          final xi = or < s.xf.length && oc < s.xf[or].length ? s.xf[or][oc] : 0;
          final st = xi < s.palette.length ? s.palette[xi] : const XfStyle();
          final rowSpan = m != null && m.r2 > m.r1, colSpan = m != null && m.c2 > m.c1;
          return TableViewCell(
            rowMergeStart: rowSpan ? m.r1 + 1 : null,
            rowMergeSpan: rowSpan ? m.r2 - m.r1 + 1 : null,
            columnMergeStart: colSpan ? m.c1 + 1 : null,
            columnMergeSpan: colSpan ? m.c2 - m.c1 + 1 : null,
            child: _data(text, st, z),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sheets[_i];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Grid')),
              ButtonSegment(value: true, label: Text('Print layout')),
            ],
            selected: {_print},
            onSelectionChanged: (v) => setState(() {
              _print = v.first;
              if (_print) _printFuture ??= widget.printView();
            }),
          ),
          const Spacer(),
          if (!_print) ...[
            IconButton(icon: const Icon(Icons.zoom_out), onPressed: _zoom > 0.6 ? () => setState(() => _zoom -= 0.2) : null),
            IconButton(icon: const Icon(Icons.zoom_in), onPressed: _zoom < 2 ? () => setState(() => _zoom += 0.2) : null),
          ],
        ]),
      ),
      if (!_print)
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6), children: [
            for (var k = 0; k < widget.sheets.length; k++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(widget.sheets[k].name), selected: k == _i, onSelected: (_) => setState(() => _i = k)),
              ),
          ]),
        ),
      const Divider(height: 1),
      Expanded(
        child: _print
            ? FutureBuilder<Widget>(
                future: _printFuture,
                builder: (c, f) => f.hasError
                    ? Center(child: Text('Print layout unavailable:\n${f.error}'))
                    : f.hasData ? f.data! : const Center(child: CircularProgressIndicator()))
            : s.rows.isEmpty ? const Center(child: Text('Empty sheet')) : _grid(s),
      ),
    ]);
  }
}
