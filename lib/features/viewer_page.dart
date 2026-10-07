import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/file_detection.dart';
import '../renderers/api.dart';
import '../renderers/renderers.dart';
import '../shared/file_style.dart';

class ViewerPage extends StatelessWidget {
  final String name;
  final Uint8List bytes;
  final FileKind kind;
  const ViewerPage({super.key, required this.name, required this.bytes, required this.kind});

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: SelectableText(v)),
        ]),
      );

  void _info(BuildContext c) => showModalBottomSheet<void>(
        context: c,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('File details', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 12),
              _row('Name', name),
              _row('Type', styleForName(name).label),
              _row('Size', formatSize(bytes.length)),
              _row('Processing', 'On this device only'),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = styleForName(name);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Icon(st.icon, color: st.color),
          const SizedBox(width: 8),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
        ]),
        actions: [
          IconButton(tooltip: 'File details', icon: const Icon(Icons.info_outline), onPressed: () => _info(context)),
        ],
      ),
      body: rendererFor(kind).build(context, OpenedFile(name, bytes, kind)),
    );
  }
}
