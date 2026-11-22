import 'ad.dart';
import 'dates.dart';

enum StatusFilter { all, unsold, sold, relistDue }

enum PostedFilter { any, posted, notPosted }

/// True when the ad is unsold and its relist reminder date is today or earlier.
bool isRelistDue(Ad ad, DateTime today) {
  if (ad.sold) return false;
  final due = parseDate(ad.relistReminder);
  if (due == null) return false;
  final t = DateTime(today.year, today.month, today.day);
  return !due.isAfter(t);
}

List<Ad> filterAds(
  List<Ad> ads, {
  String query = '',
  StatusFilter status = StatusFilter.all,
  String? platformId,
  PostedFilter posted = PostedFilter.any,
  DateTime? today,
}) {
  final q = query.trim().toLowerCase();
  final now = today ?? DateTime.now();
  return ads.where((ad) {
    if (q.isNotEmpty) {
      final hay = '${ad.title}\n${ad.description}\n${ad.category}\n'
              '${ad.condition}\n${ad.location}'
          .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    switch (status) {
      case StatusFilter.all:
        break;
      case StatusFilter.unsold:
        if (ad.sold) return false;
      case StatusFilter.sold:
        if (!ad.sold) return false;
      case StatusFilter.relistDue:
        if (!isRelistDue(ad, now)) return false;
    }
    if (posted != PostedFilter.any) {
      final isPosted = platformId == null
          ? ad.posted.values.any((v) => v)
          : ad.isPosted(platformId);
      if (posted == PostedFilter.posted && !isPosted) return false;
      if (posted == PostedFilter.notPosted && isPosted) return false;
    }
    return true;
  }).toList();
}
