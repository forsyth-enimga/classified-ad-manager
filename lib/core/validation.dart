import 'ad.dart';
import 'dates.dart';
import 'marketplaces.dart';

/// Returns field-key -> error message. Empty map = valid.
///
/// Keys: `title`, `description`, `price`, `category`, `sold_platform`,
/// `sold_price`, `sold_date`, `relist_reminder`, `posted_date.<id>`, plus the
/// storage key of any platform-specific field (e.g. `ebay.subtitle`).
Map<String, String> validateAd(Ad ad) {
  final errors = <String, String>{};

  final title = ad.title.trim();
  if (title.isEmpty) {
    errors['title'] = 'Title is required';
  } else if (title.length > kTitleMax) {
    errors['title'] = 'Title must be $kTitleMax characters or fewer';
  }

  final desc = ad.description.trim();
  if (desc.isEmpty) {
    errors['description'] = 'Description is required';
  } else if (desc.length > kDescriptionMax) {
    errors['description'] =
        'Description must be $kDescriptionMax characters or fewer';
  }

  if (ad.price == null) {
    errors['price'] = 'Price is required';
  } else if (ad.price! < 0) {
    errors['price'] = 'Price cannot be negative';
  }

  if (ad.category.trim().isEmpty) {
    errors['category'] = 'Category is required';
  }

  if (ad.sold && ad.soldPlatform.trim().isEmpty) {
    errors['sold_platform'] = 'Choose where it sold';
  }
  if (ad.soldPrice != null && ad.soldPrice! < 0) {
    errors['sold_price'] = 'Sold price cannot be negative';
  }
  if (ad.soldDate.isNotEmpty && !isValidDate(ad.soldDate)) {
    errors['sold_date'] = 'Use yyyy-MM-dd';
  }
  if (ad.relistReminder.isNotEmpty && !isValidDate(ad.relistReminder)) {
    errors['relist_reminder'] = 'Use yyyy-MM-dd';
  }
  for (final m in Marketplaces.all) {
    final d = ad.postedDate[m.id] ?? '';
    if (d.isNotEmpty && !isValidDate(d)) {
      errors['posted_date.${m.id}'] = 'Use yyyy-MM-dd';
    }
  }

  for (final m in Marketplaces.all) {
    for (final f in m.ownFields) {
      final v = ad.extraValue(f.key).trim();
      if (v.isEmpty) continue;
      if (f.type == FieldType.number && double.tryParse(v) == null) {
        errors[f.key] = '${f.label}: enter a number';
      } else if (f.maxLength != null && v.length > f.maxLength!) {
        errors[f.key] = '${f.label}: max ${f.maxLength} characters';
      } else if (f.type == FieldType.list &&
          f.maxItems != null &&
          splitList(v).length > f.maxItems!) {
        errors[f.key] = '${f.label}: max ${f.maxItems} items';
      }
    }
  }
  return errors;
}
