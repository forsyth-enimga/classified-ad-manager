import 'package:flutter/material.dart';

import '../core/importing/listing_parser.dart';
import '../core/importing/providers.dart';
import '../core/marketplaces.dart';
import '../data/import_service.dart';

/// Asks for a listing link (or pasted page source) and returns the parsed,
/// unsaved listing, or null if cancelled.
Future<ParsedListing?> showImportDialog(BuildContext context) {
  return showDialog<ParsedListing>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ImportDialog(),
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _service = ImportService();
  final _link = TextEditingController();
  final _source = TextEditingController();
  bool _pasteMode = false;
  bool _busy = false;
  String? _error;
  String _providerId = ''; // '' = auto-detect

  @override
  void dispose() {
    _link.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ParsedListing result;
      if (_pasteMode) {
        result = await _service.importFromSource(
          _source.text,
          provider: _providerId.isEmpty ? null : Marketplaces.byId(_providerId),
        );
      } else {
        result = await _service.importFromUrl(_link.text);
      }
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong while reading the page: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_pasteMode ? 'Import from pasted page source' : 'Import from link'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_pasteMode) ...[
                Text(
                  'Paste the link to one of your live listings on ${Marketplaces.all.map((m) => m.name).join(', ')}.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _link,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Listing link',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _busy ? null : _run(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Facebook Marketplace usually needs a login, and some sites block automated requests. If that happens, use pasted page source instead.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else ...[
                Text(
                  'Open the listing in your browser, press Ctrl+U (View Source), select all, copy, and paste it here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Site',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _providerId,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Auto-detect')),
                        for (final m in Marketplaces.all)
                          DropdownMenuItem(value: m.id, child: Text(m.name)),
                      ],
                      onChanged: _busy ? null : (v) => setState(() => _providerId = v ?? ''),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _source,
                  enabled: !_busy,
                  minLines: 6,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Page source',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: scheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                      ),
                    ],
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => setState(() {
                _pasteMode = !_pasteMode;
                _error = null;
              }),
          child: Text(_pasteMode ? 'Use a link instead' : 'Use pasted page source'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _run,
          child: const Text('Import'),
        ),
      ],
    );
  }
}
