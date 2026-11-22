import 'package:flutter/material.dart';

import '../core/ad.dart';
import '../data/ad_repository.dart';

/// Trashed ads: restore or delete permanently.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, required this.repo});

  final AdRepository repo;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Ad> _ads = <Ad>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ads = await widget.repo.listAds(trashed: true);
    if (!mounted) return;
    setState(() {
      _ads = ads;
      _loading = false;
    });
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _restore(Ad ad) async {
    await widget.repo.restore(ad.id!);
    await _load();
  }

  Future<void> _deleteForever(Ad ad) async {
    final ok = await _confirm(
      'Delete permanently?',
      '"${ad.title}" will be deleted for good. This cannot be undone.',
      'Delete permanently',
    );
    if (!ok) return;
    await widget.repo.deleteForever(ad.id!);
    await _load();
  }

  Future<void> _emptyTrash() async {
    final ok = await _confirm(
      'Empty trash?',
      'All ${_ads.length} ads in the trash will be deleted for good. This cannot be undone.',
      'Empty trash',
    );
    if (!ok) return;
    await widget.repo.emptyTrash();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (_ads.isNotEmpty)
            TextButton(onPressed: _emptyTrash, child: const Text('Empty trash')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ads.isEmpty
              ? const Center(child: Text('The trash is empty.'))
              : ListView.builder(
                  itemCount: _ads.length,
                  itemBuilder: (context, i) {
                    final ad = _ads[i];
                    return ListTile(
                      title: Text(ad.title),
                      subtitle: Text(ad.category),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Restore',
                            icon: const Icon(Icons.restore_from_trash),
                            onPressed: () => _restore(ad),
                          ),
                          IconButton(
                            tooltip: 'Delete permanently',
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () => _deleteForever(ad),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
