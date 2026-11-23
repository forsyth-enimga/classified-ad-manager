import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ad.dart';
import '../core/dates.dart';
import '../core/marketplaces.dart';
import '../core/validation.dart';
import '../data/ad_repository.dart';

/// Add / edit form. A new ad is an [Ad] with a null id.
class AdFormScreen extends StatefulWidget {
  const AdFormScreen({super.key, required this.repo, required this.ad, this.notice});

  final AdRepository repo;
  final Ad ad;

  /// Shown at the top (used after an import).
  final String? notice;

  @override
  State<AdFormScreen> createState() => _AdFormScreenState();
}

class _AdFormScreenState extends State<AdFormScreen> {
  late final Ad _ad;
  final Map<String, TextEditingController> _ctl = <String, TextEditingController>{};
  Map<String, String> _errors = <String, String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ad = widget.ad.copy();
    if (widget.notice != null) _errors = validateAd(_ad);
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // --- controllers ---------------------------------------------------------

  TextEditingController _c(String key, String initial) =>
      _ctl.putIfAbsent(key, () => TextEditingController(text: initial));

  /// Current text of a field: the controller if the field was ever shown,
  /// otherwise the stored value.
  String _textOf(String key, String stored) =>
      (_ctl[key]?.text ?? stored).trim();

  void _collect() {
    _ad.title = _textOf('title', _ad.title);
    _ad.description = _textOf('description', _ad.description);
    _ad.category = _textOf('category', _ad.category);
    _ad.condition = _textOf('condition', _ad.condition);
    _ad.location = _textOf('location', _ad.location);

    final priceText = _textOf('price', _ad.price?.toString() ?? '');
    _ad.price = _parseMoney(priceText);
    final soldText = _textOf('sold_price', _ad.soldPrice?.toString() ?? '');
    _ad.soldPrice = _parseMoney(soldText);

    for (final m in Marketplaces.all) {
      for (final f in m.ownFields) {
        _storeExtra(f.key, _textOf(f.key, _ad.extraValue(f.key)), f.type);
      }
      for (final e in m.overridables) {
        final key = m.overrideKey(e.shared!);
        _storeExtra(key, _textOf(key, _ad.extraValue(key)), FieldType.text);
      }
    }
  }

  /// Checkbox and dropdown values are written directly on change; everything
  /// else is stored from its text field. Blank values are removed.
  void _storeExtra(String key, String value, FieldType type) {
    if (type == FieldType.checkbox || type == FieldType.dropdown) return;
    if (value.isEmpty) {
      _ad.extra.remove(key);
    } else {
      _ad.extra[key] = value;
    }
  }

  double? _parseMoney(String s) {
    final cleaned = s.replaceAll(',', '.').replaceAll('\$', '').trim();
    return cleaned.isEmpty ? null : double.tryParse(cleaned);
  }

  // --- save ----------------------------------------------------------------

  Future<void> _save() async {
    _collect();
    final errors = validateAd(_ad);
    final priceText = _textOf('price', '');
    if (priceText.isNotEmpty && _ad.price == null) {
      errors['price'] = 'Enter a valid amount';
    }
    final soldText = _textOf('sold_price', '');
    if (soldText.isNotEmpty && _ad.soldPrice == null) {
      errors['sold_price'] = 'Enter a valid amount';
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fix: ${errors.values.first}')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (_ad.id == null) {
        await widget.repo.insert(_ad);
      } else {
        await widget.repo.update(_ad);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  // --- small widgets -------------------------------------------------------

  Widget _pad(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: child);

  Widget _section(String title, {String? subtitle}) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null)
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );

  Widget _textField({
    required String key,
    required String label,
    required String initial,
    String? helper,
    int? maxLength,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) {
    return _pad(
      TextField(
        controller: _c(key, initial),
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboard ??
            (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        inputFormatters: formatters,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          errorText: _errors[key],
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    String? errorText,
  }) {
    final current = options.contains(value) ? value : '';
    return _pad(
      InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: current,
            isExpanded: true,
            isDense: true,
            items: [
              const DropdownMenuItem<String>(value: '', child: Text('—')),
              for (final o in options)
                DropdownMenuItem<String>(value: o, child: Text(o)),
            ],
            onChanged: (v) => onChanged(v ?? ''),
          ),
        ),
      ),
    );
  }

  Widget _dateRow({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? errorText,
  }) {
    return _pad(
      Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: parseDate(value) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) onChanged(fmtDate(picked));
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(value.isEmpty ? 'Not set' : value),
              ),
            ),
          ),
          if (value.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: () => onChanged(''),
            ),
        ],
      ),
    );
  }

  /// A platform-specific field, drawn by type.
  Widget _fieldWidget(FieldDef f) {
    switch (f.type) {
      case FieldType.checkbox:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _ad.extraBool(f.key),
          onChanged: (v) =>
              setState(() => _ad.extra[f.key] = v ? 'true' : 'false'),
        );
      case FieldType.dropdown:
        return _dropdown(
          label: f.label,
          value: _ad.extraValue(f.key),
          options: f.options,
          onChanged: (v) => setState(() {
            if (v.isEmpty) {
              _ad.extra.remove(f.key);
            } else {
              _ad.extra[f.key] = v;
            }
          }),
          errorText: _errors[f.key],
        );
      case FieldType.number:
        return _textField(
          key: f.key,
          label: f.label,
          initial: _ad.extraValue(f.key),
          helper: f.hint,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        );
      case FieldType.multiline:
        return _textField(
          key: f.key,
          label: f.label,
          initial: _ad.extraValue(f.key),
          helper: f.hint,
          maxLength: f.maxLength,
          minLines: 2,
          maxLines: 6,
        );
      case FieldType.list:
      case FieldType.text:
        return _textField(
          key: f.key,
          label: f.label,
          initial: _ad.extraValue(f.key),
          helper: f.hint,
          maxLength: f.maxLength,
        );
    }
  }

  Widget _marketplaceTile(Marketplace m) {
    final children = <Widget>[
      for (final e in m.overridables)
        _textField(
          key: m.overrideKey(e.shared!),
          label: '${e.label} (override for ${m.name})',
          initial: _ad.extraValue(m.overrideKey(e.shared!)),
          helper: 'Leave blank to use the shared ${e.shared!.name}',
        ),
      for (final f in m.ownFields) _fieldWidget(f),
    ];
    return ExpansionTile(
      title: Text(m.name),
      subtitle: const Text('Optional platform-specific fields'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isNew = _ad.id == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New ad' : 'Edit ad'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            children: [
              if (widget.notice != null)
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 8),
                        Expanded(child: Text(widget.notice!)),
                      ],
                    ),
                  ),
                ),
              _section('Required for every platform'),
              _textField(
                key: 'title',
                label: 'Title *',
                initial: _ad.title,
                maxLength: kTitleMax,
              ),
              _textField(
                key: 'description',
                label: 'Description *',
                initial: _ad.description,
                maxLength: kDescriptionMax,
                minLines: 4,
                maxLines: 10,
                helper: 'Line breaks are kept in the export files.',
              ),
              _textField(
                key: 'price',
                label: 'Price *',
                initial: _ad.price == null ? '' : _ad.price!.toString(),
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              _textField(
                key: 'category',
                label: 'Category *',
                initial: _ad.category,
                helper:
                    'Free text, e.g. Buy & Sell > Books > Comics. Each platform can override it below.',
              ),
              _section('Optional shared fields'),
              _textField(
                key: 'condition',
                label: 'Condition',
                initial: _ad.condition,
              ),
              _textField(
                key: 'location',
                label: 'Location',
                initial: _ad.location,
                helper: 'City / postal code / where to meet.',
              ),
              _section(
                'Platform details',
                subtitle:
                    'Only the fields a platform has are written to its export file.',
              ),
              for (final m in Marketplaces.all) _marketplaceTile(m),
              _section('Posted on'),
              for (final m in Marketplaces.all) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(m.name),
                  value: _ad.isPosted(m.id),
                  onChanged: (v) => setState(() {
                    _ad.posted[m.id] = v ?? false;
                    if (v == true && (_ad.postedDate[m.id] ?? '').isEmpty) {
                      _ad.postedDate[m.id] = fmtDate(DateTime.now());
                    }
                    if (v != true) _ad.postedDate[m.id] = '';
                  }),
                ),
                if (_ad.isPosted(m.id))
                  _dateRow(
                    label: 'Posted date (${m.name})',
                    value: _ad.postedDate[m.id] ?? '',
                    errorText: _errors['posted_date.${m.id}'],
                    onChanged: (v) =>
                        setState(() => _ad.postedDate[m.id] = v),
                  ),
              ],
              _section('Sold'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sold'),
                value: _ad.sold,
                onChanged: (v) => setState(() {
                  _ad.sold = v;
                  if (v && _ad.soldDate.isEmpty) {
                    _ad.soldDate = fmtDate(DateTime.now());
                  }
                }),
              ),
              if (_ad.sold) ...[
                _dropdown(
                  label: 'Sold on',
                  value: _ad.soldPlatform,
                  options: <String>[
                    for (final m in Marketplaces.all) m.name,
                    kSoldElsewhere,
                  ],
                  onChanged: (v) => setState(() => _ad.soldPlatform = v),
                  errorText: _errors['sold_platform'],
                ),
                _textField(
                  key: 'sold_price',
                  label: 'Sold price',
                  initial: _ad.soldPrice == null ? '' : _ad.soldPrice!.toString(),
                  keyboard:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                _dateRow(
                  label: 'Sold date',
                  value: _ad.soldDate,
                  errorText: _errors['sold_date'],
                  onChanged: (v) => setState(() => _ad.soldDate = v),
                ),
              ],
              _section('Relist reminder'),
              _dateRow(
                label: 'Remind me to relist on',
                value: _ad.relistReminder,
                errorText: _errors['relist_reminder'],
                onChanged: (v) => setState(() => _ad.relistReminder = v),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Save ad'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
