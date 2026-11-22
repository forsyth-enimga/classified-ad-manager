/// The ad record. Pure Dart so it can be unit-checked without Flutter.
///
/// Shared (mandatory) fields are real properties. Platform-specific optional
/// fields live in [extra], keyed like `ebay.subtitle`. Checkbox values are
/// stored as the strings `true` / `false`.
class Ad {
  Ad({
    this.id,
    this.title = '',
    this.description = '',
    this.price,
    this.category = '',
    this.condition = '',
    this.location = '',
    Map<String, String>? extra,
    Map<String, bool>? posted,
    Map<String, String>? postedDate,
    this.sold = false,
    this.soldPlatform = '',
    this.soldPrice,
    this.soldDate = '',
    this.relistReminder = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  })  : extra = extra ?? <String, String>{},
        posted = posted ?? <String, bool>{},
        postedDate = postedDate ?? <String, String>{},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int? id;

  // Shared fields (title, description, price and category are mandatory).
  String title;
  String description;
  double? price;
  String category;
  String condition; // optional
  String location; // optional

  /// Platform-specific optional values, e.g. `ebay.subtitle` -> `Free shipping`.
  final Map<String, String> extra;

  /// Posted checkbox per marketplace id, plus the date it was posted (yyyy-MM-dd).
  final Map<String, bool> posted;
  final Map<String, String> postedDate;

  // Sold tracking.
  bool sold;
  String soldPlatform; // marketplace name, or "Local / in person / other"
  double? soldPrice;
  String soldDate; // yyyy-MM-dd

  /// Optional date (yyyy-MM-dd) when the ad should be relisted.
  String relistReminder;

  DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt; // non-null = in the trash

  bool get isTrashed => deletedAt != null;

  bool isPosted(String marketplaceId) => posted[marketplaceId] ?? false;

  String extraValue(String key) => extra[key] ?? '';

  bool extraBool(String key) => extra[key] == 'true';

  /// A full independent copy (used by the edit form so Cancel discards changes).
  Ad copy() => Ad(
        id: id,
        title: title,
        description: description,
        price: price,
        category: category,
        condition: condition,
        location: location,
        extra: Map<String, String>.from(extra),
        posted: Map<String, bool>.from(posted),
        postedDate: Map<String, String>.from(postedDate),
        sold: sold,
        soldPlatform: soldPlatform,
        soldPrice: soldPrice,
        soldDate: soldDate,
        relistReminder: relistReminder,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );

  /// A new, unsaved ad based on this one: content is kept, but posting, sold
  /// and reminder state is reset.
  Ad cloneForNew({int titleMax = 80}) {
    const suffix = ' (copy)';
    var newTitle = title;
    if (newTitle.length + suffix.length > titleMax) {
      newTitle = newTitle.substring(0, titleMax - suffix.length);
    }
    return Ad(
      title: '$newTitle$suffix',
      description: description,
      price: price,
      category: category,
      condition: condition,
      location: location,
      extra: Map<String, String>.from(extra),
    );
  }
}
