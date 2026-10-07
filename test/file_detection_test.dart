import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:omniview/core/file_detection.dart';
import 'package:omniview/renderers/xlsx_parser.dart';

ArchiveFile _f(String n, String s) {
  final b = utf8.encode(s);
  return ArchiveFile(n, b.length, b);
}

void main() {
  test('PDF detected by signature despite wrong extension', () {
    expect(detectKind('a.txt', Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2d])), FileKind.pdf);
  });
  test('docx vs plain zip', () {
    final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
    expect(detectKind('r.docx', zip), FileKind.docx);
    expect(detectKind('r.zip', zip), FileKind.zip);
  });
  test('binary garbage is not shown as text', () {
    expect(detectKind('x.dat', Uint8List.fromList([1, 0, 2, 0])), FileKind.binary);
  });
  test('markdown and csv by extension', () {
    final t = Uint8List.fromList('hi'.codeUnits);
    expect(detectKind('n.md', t), FileKind.markdown);
    expect(detectKind('d.tsv', t), FileKind.csv);
  });
  test('legacy Office and ODF route to the engine', () {
    final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
    final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
    expect(detectKind('a.doc', ole), FileKind.office);
    expect(detectKind('a.ppt', ole), FileKind.office);
    expect(detectKind('a.odt', zip), FileKind.office);
    expect(detectKind('a.odp', zip), FileKind.office);
    expect(detectKind('a.msg', ole), FileKind.binary);
    expect(detectKind('a.rtf', Uint8List.fromList(r'{\rtf1'.codeUnits)), FileKind.office);
  });
  test('sheet and image kinds', () {
    final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
    final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
    expect(detectKind('a.xls', ole), FileKind.convSheet);
    expect(detectKind('a.ods', zip), FileKind.convSheet);
    expect(detectKind('a.tif', Uint8List.fromList([0x49, 0x49, 0x2A, 0x00])), FileKind.image);
    expect(detectKind('a.svg', Uint8List.fromList('<svg/>'.codeUnits)), FileKind.svg);
  });
  test('password-protected OOXML (OLE container) is flagged', () {
    final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
    expect(detectKind('secret.docx', ole), FileKind.encrypted);
    expect(detectKind('secret.xlsx', ole), FileKind.encrypted);
    expect(detectKind('old.doc', ole), FileKind.office);
  });
  test('notebook kind', () {
    expect(detectKind('a.ipynb', Uint8List.fromList('{}'.codeUnits)), FileKind.notebook);
  });
  test('xlsx grid: strings, numbers, dates, thousands', () {
    final ar = Archive()
      ..addFile(_f('xl/workbook.xml', '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>'))
      ..addFile(_f('xl/_rels/workbook.xml.rels', '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'))
      ..addFile(_f('xl/sharedStrings.xml', '<sst><si><t>Name</t></si></sst>'))
      ..addFile(_f('xl/styles.xml', '<styleSheet><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="4"/></cellXfs></styleSheet>'))
      ..addFile(_f('xl/worksheets/sheet1.xml', '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><v>3.5</v></c><c r="C1" s="1"><v>45000</v></c><c r="D1" s="2"><v>1234567.891</v></c></row></sheetData></worksheet>'));
    final sheets = parseXlsx(Uint8List.fromList(ZipEncoder().encode(ar)!));
    expect(sheets.single.name, 'Data');
    expect(sheets.single.rows.first, ['Name', '3.5', '2023-03-15', '1,234,567.89']);
  });
  test('xlsx styles, merges, frozen panes, sizes', () {
    final ar = Archive()
      ..addFile(_f('xl/workbook.xml', '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>'))
      ..addFile(_f('xl/_rels/workbook.xml.rels', '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'))
      ..addFile(_f('xl/styles.xml', '<styleSheet><fonts><font/><font><b/><sz val="14"/><color rgb="FFFF0000"/></font></fonts><fills><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFFF00"/></patternFill></fill></fills><cellXfs><xf numFmtId="0" fontId="0" fillId="0"/><xf numFmtId="0" fontId="1" fillId="1"><alignment horizontal="center"/></xf></cellXfs></styleSheet>'))
      ..addFile(_f('xl/worksheets/sheet1.xml', '<worksheet><sheetViews><sheetView><pane xSplit="1" ySplit="2" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="2" width="20" customWidth="1"/></cols><sheetData><row r="1" ht="30"><c r="A1" s="1"><v>1</v></c></row></sheetData><mergeCells><mergeCell ref="A1:B2"/></mergeCells></worksheet>'));
    final sh = parseXlsx(Uint8List.fromList(ZipEncoder().encode(ar)!)).single;
    expect(sh.palette[1].bold, true);
    expect(sh.palette[1].fill, 0xFFFFFF00);
    expect(sh.palette[1].color, 0xFFFF0000);
    expect(sh.palette[1].align, 'center');
    expect(sh.xf[0][0], 1);
    expect((sh.merges.single.r2, sh.merges.single.c2), (1, 1));
    expect((sh.freezeRows, sh.freezeCols), (2, 1));
    expect(sh.colPx[0], 145);
    expect(sh.rowPx[0], 40);
  });
}
