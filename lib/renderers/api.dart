import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import '../core/file_detection.dart';

class OpenedFile {
  final String name;
  final Uint8List bytes;
  final FileKind kind;
  const OpenedFile(this.name, this.bytes, this.kind);
}

/// Each format implements this; the UI never knows format internals.
abstract interface class FileRenderer {
  bool supports(FileKind kind);
  Widget build(BuildContext context, OpenedFile file);
}
