import 'package:flutter/material.dart';

class FileStyle {
  final IconData icon;
  final Color color;
  final String label;
  const FileStyle(this.icon, this.color, this.label);
}

const _code = {
  'py', 'java', 'c', 'cpp', 'cc', 'h', 'hpp', 'js', 'ts', 'tsx', 'dart', 'kt', 'swift', 'go', 'rs', 'php',
  'rb', 'cs', 'sql', 'sh', 'html', 'css', 'xml', 'yaml', 'yml', 'toml', 'json', 'jsonc', 'ini', 'log', 'txt'
};

/// Icon, colour and label for a file, chosen from its extension (used by recents and the viewer).
FileStyle styleForName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (ext == 'pdf') return const FileStyle(Icons.picture_as_pdf, Color(0xFFE5484D), 'PDF document');
  if ({'doc', 'docx', 'dotx', 'docm', 'odt', 'rtf'}.contains(ext)) {
    return const FileStyle(Icons.description, Color(0xFF2B6CD9), 'Word / text document');
  }
  if ({'xls', 'xlsx', 'xlsm', 'xltx', 'ods'}.contains(ext)) {
    return const FileStyle(Icons.table_chart, Color(0xFF1F9D55), 'Spreadsheet');
  }
  if ({'csv', 'tsv'}.contains(ext)) return const FileStyle(Icons.grid_on, Color(0xFF1F9D55), 'Table (CSV)');
  if ({'ppt', 'pptx', 'ppsx', 'potx', 'odp'}.contains(ext)) {
    return const FileStyle(Icons.slideshow, Color(0xFFE8710A), 'Presentation');
  }
  if ({'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'ico', 'svg', 'heic', 'heif', 'avif'}.contains(ext)) {
    return const FileStyle(Icons.image, Color(0xFF8E4EC6), 'Image');
  }
  if (ext == 'zip') return const FileStyle(Icons.folder_zip, Color(0xFFB7791F), 'Archive');
  if (ext == 'ipynb') return const FileStyle(Icons.science, Color(0xFFF76808), 'Jupyter notebook');
  if (ext == 'md' || ext == 'markdown') return const FileStyle(Icons.article, Color(0xFF0E9AA7), 'Markdown');
  if (_code.contains(ext)) return const FileStyle(Icons.code, Color(0xFF5B6B8C), 'Text / code');
  return const FileStyle(Icons.insert_drive_file, Color(0xFF7A869A), 'File');
}

String formatSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}
