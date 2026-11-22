import 'package:flutter/material.dart';

import '../core/ad.dart';
import '../core/ad_filter.dart';
import '../core/marketplaces.dart';
import '../data/ad_repository.dart';
import 'ad_form_screen.dart';
import 'export_actions.dart';
import 'trash_screen.dart';

class AdListScreen extends StatefulWidget {
  const AdListScreen({super.key, required this.repo});

  final AdRepository repo;

  @override
  State<AdListScreen> createState() => _AdListScreenState();
}

enum _Action { edit, clone, export, trash }

class _AdListScreenState extends State<AdListScreen> {
  List<Ad> _ads = <Ad>[];
  bool _loading = true;
  String _query = '';
  StatusFilter _status = StatusFilter.all;
  String? _platformId;
  PostedFilter _posted = PostedFilter.any;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ads = await widget.repo.listAds();
    if (!mounted) return;
    setState(() {
      _ads = ads;
      _loading = false;
    });
  }

  Future<void> _openForm(Ad ad) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AdFormScreen(repo: widget.repo, ad: ad),
      ),
    );
    await _load();
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => TrashScreen(repo: widget.repo)),
    );
    await _load();
  }

  Future<void> _confirmTrash(Ad ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to trash?'),
        content: Text(
            '"${ad.title}" will be moved to the trash. You can restore it or delete it permanently from there.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );
    if (ok == true && ad.id != null) {
      await widget.repo.moveToTrash(ad.id!);
      await _load();
    }
  }

  void _onAction(_Action action, Ad ad) {
    switch (action) {
      case _Action.edit:
        _openForm(ad);
      case _Action.clone:
        _openForm(ad.cloneForNew());
      case _Action.export:
        showExportSheet(context, ad);
      case _Action.trash:
        _confirmTrash(ad);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterAds(
      _ads,
      query: _query,
      status: _status,
      platformId: _platformId,
      posted: _posted,
    );
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classified Ad Manager'),
        actions: [
          IconButton(
            tooltip: 'Trash',
            icon: const Icon(Icons.delete_outline),
            onPressed: _openTrash,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(Ad()),
        icon: const Icon(Icons.add),
        label: const Text('New ad'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              _buildFilters(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : visible.isEmpty
                        ? Center(
                            child: Text(_ads.isEmpty
                                ? 'No ads yet. Tap "New ad" to add one.'
                                : 'No ads match the current filters.'),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: visible.length,
                            itemBuilder: (context, i) =>
                                _buildTile(visible[i], today),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search title, description, category...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in const <StatusFilter, String>{
                StatusFilter.all: 'All',
                StatusFilter.unsold: 'Unsold',
                StatusFilter.sold: 'Sold',
                StatusFilter.relistDue: 'Relist due',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _status == entry.key,
                  onSelected: (_) => setState(() => _status = entry.key),
                ),
              DropdownButton<String?>(
                value: _platformId,
                hint: const Text('Any platform'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Any platform'),
                  ),
                  for (final m in Marketplaces.all)
                    DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
                ],
                onChanged: (v) => setState(() => _platformId = v),
              ),
              DropdownButton<PostedFilter>(
                value: _posted,
                items: const [
                  DropdownMenuItem(
                      value: PostedFilter.any, child: Text('Posted or not')),
                  DropdownMenuItem(
                      value: PostedFilter.posted, child: Text('Posted')),
                  DropdownMenuItem(
                      value: PostedFilter.notPosted, child: Text('Not posted')),
                ],
                onChanged: (v) =>
                    setState(() => _posted = v ?? PostedFilter.any),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTile(Ad ad, DateTime today) {
    final scheme = Theme.of(context).colorScheme;
    final postedOn = Marketplaces.all.where((m) => ad.isPosted(m.id)).toList();
    final price = ad.price == null ? '' : '\$${ad.price!.toStringAsFixed(2)}';

    final chips = <Widget>[
      if (ad.sold)
        Chip(
          visualDensity: VisualDensity.compact,
          backgroundColor: scheme.primaryContainer,
          label: Text(
            ad.soldPlatform.isEmpty
                ? 'Sold'
                : 'Sold on ${ad.soldPlatform}'
                    '${ad.soldPrice == null ? '' : ' for \$${ad.soldPrice!.toStringAsFixed(2)}'}',
          ),
        ),
      if (isRelistDue(ad, today))
        Chip(
          visualDensity: VisualDensity.compact,
          backgroundColor: scheme.errorContainer,
          label: const Text('Relist due'),
        ),
      for (final m in postedOn)
        Chip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.check, size: 16),
          label: Text(m.name),
        ),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => _openForm(ad),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text('$price  •  ${ad.category}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 0, children: chips),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<_Action>(
                onSelected: (a) => _onAction(a, ad),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _Action.edit, child: Text('Edit')),
                  PopupMenuItem(value: _Action.clone, child: Text('Clone')),
                  PopupMenuItem(value: _Action.export, child: Text('Export...')),
                  PopupMenuItem(
                      value: _Action.trash, child: Text('Move to trash')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
