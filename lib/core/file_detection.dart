import 'dart:typed_data';

/// `office` = formats that need the LibreOffice engine: legacy DOC/XLS/PPT, ODF (ODT/ODS/ODP), RTF.
enum FileKind { pdf, docx, xlsx, pptx, office, convSheet, encrypted, svg, notebook, markdown, json, csv, image, zip, text, binary }

const _img = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
const _ole = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]; // legacy Office container
const _oleExt = {'doc', 'xls', 'ppt', 'dot', 'xlt', 'pot', 'pps'};
const _odfExt = {'odt', 'ods', 'odp', 'ott', 'ots', 'otp'};

bool _starts(Uint8List h, List<int> s) =>
    h.length >= s.length && [for (var i = 0; i < s.length; i++) h[i] == s[i]].every((e) => e);

/// Detects by magic bytes first, then extension. Extension alone is never trusted for binaries.
FileKind detectKind(String name, Uint8List head) {
  final lower = name.toLowerCase();
  final ext = lower.contains('.') ? lower.split('.').last : lower;
  if (_starts(head, [0x25, 0x50, 0x44, 0x46])) return FileKind.pdf;
  if (_starts(head, _ole)) {
    // Password-protected OOXML files are stored in an OLE container instead of a ZIP.
    if (const {'docx', 'xlsx', 'pptx', 'dotx', 'xltx', 'potx', 'docm', 'xlsm', 'pptm', 'ppsx'}.contains(ext)) {
      return FileKind.encrypted;
    }
    if (ext == 'xls' || ext == 'xlt') return FileKind.convSheet;
    return _oleExt.contains(ext) ? FileKind.office : FileKind.binary;
  }
  if (_starts(head, [0x50, 0x4B, 0x03, 0x04])) {
    return switch (ext) {
      'docx' || 'dotx' || 'docm' => FileKind.docx,
      'xlsx' || 'xltx' || 'xlsm' => FileKind.xlsx,
      'pptx' || 'ppsx' || 'potx' || 'pptm' => FileKind.pptx,
      'ods' || 'ots' => FileKind.convSheet,
      _ when _odfExt.contains(ext) => FileKind.office,
      _ => FileKind.zip,
    };
  }
  if (ext == 'rtf' && _starts(head, [0x7B, 0x5C, 0x72, 0x74, 0x66])) return FileKind.office;
  if (_starts(head, [0x89, 0x50, 0x4E, 0x47]) ||
      _starts(head, [0xFF, 0xD8, 0xFF]) ||
      _starts(head, [0x47, 0x49, 0x46, 0x38]) ||
      _starts(head, [0x49, 0x49, 0x2A, 0x00]) || // TIFF little-endian
      _starts(head, [0x4D, 0x4D, 0x00, 0x2A]) || // TIFF big-endian
      (_starts(head, [0x00, 0x00, 0x01, 0x00]) && ext == 'ico') ||
      (_starts(head, [0x52, 0x49, 0x46, 0x46]) && _img.contains(ext)) ||
      (_starts(head, [0x42, 0x4D]) && ext == 'bmp')) {
    return FileKind.image;
  }
  if (head.length >= 12 && _starts(Uint8List.fromList(head.sublist(4, 8)), [0x66, 0x74, 0x79, 0x70]) &&
      const {'heic', 'heif', 'avif'}.contains(ext)) {
    return FileKind.image; // HEIF/AVIF container, decoded natively on Android
  }
  if (head.take(512).contains(0)) return FileKind.binary;
  if (ext == 'svg') return FileKind.svg;
  if (ext == 'ipynb') return FileKind.notebook;
  if (ext == 'md' || ext == 'markdown') return FileKind.markdown;
  if (ext == 'json' || ext == 'jsonc') return FileKind.json;
  if (ext == 'csv' || ext == 'tsv') return FileKind.csv;
  return FileKind.text;
}
