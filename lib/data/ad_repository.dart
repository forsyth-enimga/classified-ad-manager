import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/ad.dart';
import '../core/marketplaces.dart';

/// Local SQLite storage. One table, `ads`. A row with `deleted_at` set is in
/// the trash. Platform "posted" checkboxes and dates are real columns
/// (`posted_<id>`, `posted_date_<id>`); platform-specific optional fields are
/// stored as JSON in `extra`.
class AdRepository {
  AdRepository._(this._db);

  final Database _db;

  static Future<AdRepository> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path = p.join(dir.path, 'classified_ads.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute(_createSql()),
    );
    return AdRepository._(db);
  }

  static String _createSql() {
    final posted = StringBuffer();
    for (final m in Marketplaces.all) {
      posted.writeln('  posted_${m.id} INTEGER NOT NULL DEFAULT 0,');
      posted.writeln("  posted_date_${m.id} TEXT NOT NULL DEFAULT '',");
    }
    return '''
CREATE TABLE ads (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  price REAL,
  category TEXT NOT NULL,
  item_condition TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  extra TEXT NOT NULL DEFAULT '{}',
$posted  sold INTEGER NOT NULL DEFAULT 0,
  sold_platform TEXT NOT NULL DEFAULT '',
  sold_price REAL,
  sold_date TEXT NOT NULL DEFAULT '',
  relist_reminder TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)''';
  }

  Map<String, Object?> _toRow(Ad ad) {
    final row = <String, Object?>{
      'title': ad.title.trim(),
      'description': ad.description.trim(),
      'price': ad.price,
      'category': ad.category.trim(),
      'item_condition': ad.condition.trim(),
      'location': ad.location.trim(),
      'extra': jsonEncode(ad.extra),
      'sold': ad.sold ? 1 : 0,
      'sold_platform': ad.soldPlatform,
      'sold_price': ad.soldPrice,
      'sold_date': ad.soldDate,
      'relist_reminder': ad.relistReminder,
      'created_at': ad.createdAt.toIso8601String(),
      'updated_at': ad.updatedAt.toIso8601String(),
      'deleted_at': ad.deletedAt?.toIso8601String(),
    };
    for (final m in Marketplaces.all) {
      row['posted_${m.id}'] = ad.isPosted(m.id) ? 1 : 0;
      row['posted_date_${m.id}'] = ad.postedDate[m.id] ?? '';
    }
    return row;
  }

  Ad _fromRow(Map<String, Object?> r) {
    final extra = <String, String>{};
    final decoded = jsonDecode((r['extra'] as String?) ?? '{}');
    if (decoded is Map) {
      decoded.forEach((k, v) => extra[k.toString()] = v?.toString() ?? '');
    }
    final posted = <String, bool>{};
    final postedDate = <String, String>{};
    for (final m in Marketplaces.all) {
      posted[m.id] = (r['posted_${m.id}'] as int? ?? 0) == 1;
      postedDate[m.id] = (r['posted_date_${m.id}'] as String?) ?? '';
    }
    final deleted = r['deleted_at'] as String?;
    return Ad(
      id: r['id'] as int?,
      title: r['title'] as String? ?? '',
      description: r['description'] as String? ?? '',
      price: (r['price'] as num?)?.toDouble(),
      category: r['category'] as String? ?? '',
      condition: r['item_condition'] as String? ?? '',
      location: r['location'] as String? ?? '',
      extra: extra,
      posted: posted,
      postedDate: postedDate,
      sold: (r['sold'] as int? ?? 0) == 1,
      soldPlatform: r['sold_platform'] as String? ?? '',
      soldPrice: (r['sold_price'] as num?)?.toDouble(),
      soldDate: r['sold_date'] as String? ?? '',
      relistReminder: r['relist_reminder'] as String? ?? '',
      createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(r['updated_at'] as String? ?? ''),
      deletedAt: deleted == null ? null : DateTime.tryParse(deleted),
    );
  }

  /// Active ads (default) or, with [trashed], the ads in the trash.
  Future<List<Ad>> listAds({bool trashed = false}) async {
    final rows = await _db.query(
      'ads',
      where: trashed ? 'deleted_at IS NOT NULL' : 'deleted_at IS NULL',
      orderBy: trashed ? 'deleted_at DESC' : 'updated_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<int> insert(Ad ad) async {
    final now = DateTime.now();
    ad.createdAt = now;
    ad.updatedAt = now;
    final id = await _db.insert('ads', _toRow(ad));
    ad.id = id;
    return id;
  }

  Future<void> update(Ad ad) async {
    ad.updatedAt = DateTime.now();
    await _db.update('ads', _toRow(ad), where: 'id = ?', whereArgs: [ad.id]);
  }

  Future<void> moveToTrash(int id) => _db.update(
        'ads',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> restore(int id) => _db.update(
        'ads',
        {'deleted_at': null},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> deleteForever(int id) =>
      _db.delete('ads', where: 'id = ? AND deleted_at IS NOT NULL', whereArgs: [id]);

  Future<void> emptyTrash() =>
      _db.delete('ads', where: 'deleted_at IS NOT NULL');
}
