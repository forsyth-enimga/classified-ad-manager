import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/ad.dart';
import '../core/exporter.dart';
import '../core/marketplaces.dart';
import 'file_saver.dart';

/// Bottom sheet: one platform (.txt) or all platforms (.zip).
Future<void> showExportSheet(BuildContext context, Ad ad) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Export ad'),
            subtitle: Text('You will be asked where to save the file.'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: const Text('All platforms'),
            subtitle: const Text('One .txt per platform, bundled in a .zip'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              exportAll(context, ad);
            },
          ),
          const Divider(height: 1),
          for (final m in Marketplaces.all)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(m.name),
              subtitle: Text(exportFileName(ad, m)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                exportOne(context, ad, m);
              },
            ),
        ],
      ),
    ),
  );
}

Future<bool> _confirmWarnings(BuildContext context, List<String> warnings) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Check before exporting'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final w in warnings) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• $w'),
          )],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Export anyway'),
        ),
      ],
    ),
  );
  return go == true;
}

void _toast(ScaffoldMessengerState messenger, String message) {
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

Future<void> exportOne(BuildContext context, Ad ad, Marketplace m) async {
  // Captured before any await so no BuildContext is used across async gaps.
  final messenger = ScaffoldMessenger.of(context);
  final warnings = exportWarnings(m, ad);
  if (warnings.isNotEmpty && !await _confirmWarnings(context, warnings)) return;
  try {
    final bytes = Uint8List.fromList(utf8.encode(buildExportText(m, ad)));
    final saved = await saveBytes(
      fileName: exportFileName(ad, m),
      bytes: bytes,
      extension: 'txt',
      dialogTitle: 'Save ${m.name} export',
    );
    _toast(messenger, saved == null ? 'Export cancelled' : 'Saved ${m.name} export');
  } catch (e) {
    _toast(messenger, 'Export failed: $e');
  }
}

Future<void> exportAll(BuildContext context, Ad ad) async {
  final messenger = ScaffoldMessenger.of(context);
  final warnings = <String>[
    for (final m in Marketplaces.all)
      for (final w in exportWarnings(m, ad)) w,
  ];
  if (warnings.isNotEmpty && !await _confirmWarnings(context, warnings)) return;
  try {
    final saved = await saveBytes(
      fileName: exportZipName(ad),
      bytes: buildAllZip(ad),
      extension: 'zip',
      dialogTitle: 'Save all-platform export',
    );
    _toast(messenger, saved == null ? 'Export cancelled' : 'Saved all-platform export');
  } catch (e) {
    _toast(messenger, 'Export failed: $e');
  }
}
