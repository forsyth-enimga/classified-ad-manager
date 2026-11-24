import 'ad.dart';

/// Lowest common limits across all platforms (agreed with the user).
const int kTitleMax = 80;
const int kDescriptionMax = 1000;

/// Poshmark has been reported to cut descriptions at 500 characters (other
/// sources say 1,500). Longer descriptions export with a warning.
const int kPoshmarkDescriptionWarn = 500;

/// Depop has no title field: title + description + hashtags share one box.
const int kDepopTextMax = 1000;
const int kDepopMaxHashtags = 5;

/// Value used in the "sold on" dropdown for sales outside the 7 platforms.
const String kSoldElsewhere = 'Local / in person / other';

enum SharedKey { title, description, price, category, condition, location }

enum FieldType { text, multiline, number, dropdown, checkbox, list }

/// A platform-specific, optional field.
class FieldDef {
  const FieldDef(
    this.key,
    this.label,
    this.type, {
    this.maxLength,
    this.maxItems,
    this.options = const <String>[],
    this.hint,
  });

  /// Storage key inside [Ad.extra], e.g. `ebay.subtitle`.
  final String key;

  /// The label exactly as the platform shows it. Also used in the export file.
  final String label;
  final FieldType type;
  final int? maxLength;
  final int? maxItems;
  final List<String> options;
  final String? hint;
}

typedef ComputedValue = String Function(Ad ad);

/// One line item of a platform's export file, in platform form order.
class Entry {
  /// A value taken from a shared field. If [overridable], the ad may hold a
  /// platform-specific override (stored as `<marketplaceId>.<sharedKey>`).
  Entry.shared(this.label, this.shared, {this.overridable = false})
      : field = null,
        computed = null;

  /// A platform-only field.
  Entry.own(FieldDef def)
      : label = def.label,
        shared = null,
        field = def,
        computed = null,
        overridable = false;

  /// A value built from several fields (used by Depop's combined description).
  Entry.computed(this.label, this.computed)
      : shared = null,
        field = null,
        overridable = false;

  final String label;
  final SharedKey? shared;
  final FieldDef? field;
  final ComputedValue? computed;
  final bool overridable;
}

class Marketplace {
  Marketplace({
    required this.id,
    required this.name,
    required this.entries,
    this.formOnly = const <FieldDef>[],
  });

  final String id;
  final String name;

  /// Export order. Only these fields are written to the export file.
  final List<Entry> entries;

  /// Fields that appear in the form but are folded into another export entry.
  final List<FieldDef> formOnly;

  /// Link to the live listing (filled by "Import from link"; never exported).
  FieldDef get listingUrlField => FieldDef(
        '$id.listing_url',
        'Listing URL',
        FieldType.text,
        hint: 'Link to your live listing on $name',
      );

  List<FieldDef> get ownFields => <FieldDef>[
        for (final e in entries)
          if (e.field != null) e.field!,
        ...formOnly,
        listingUrlField,
      ];

  List<Entry> get overridables =>
      entries.where((e) => e.overridable).toList(growable: false);

  String overrideKey(SharedKey k) => '$id.${k.name}';
}

List<String> splitList(String raw) => raw
    .split(RegExp(r'[,\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Hashtags typed as "#vintage #nike", "vintage, nike" or a mix -> "#vintage #nike".
List<String> depopHashtagList(Ad ad) => ad
    .extraValue('depop.hashtags')
    .split(RegExp(r'[,\s]+'))
    .map((t) => t.replaceFirst(RegExp(r'^#+'), '').trim())
    .where((t) => t.isNotEmpty)
    .map((t) => '#$t')
    .toList();

/// Depop has a single Description box: title first, then description, then hashtags.
String depopDescription(Ad ad) {
  final parts = <String>[
    ad.title.trim(),
    ad.description.trim(),
    depopHashtagList(ad).join(' '),
  ].where((p) => p.isNotEmpty);
  return parts.join('\n\n');
}

FieldDef _text(String key, String label, {int? maxLength, String? hint}) =>
    FieldDef(key, label, FieldType.text, maxLength: maxLength, hint: hint);

FieldDef _multi(String key, String label, {int? maxLength, String? hint}) =>
    FieldDef(key, label, FieldType.multiline, maxLength: maxLength, hint: hint);

FieldDef _num(String key, String label, {String? hint}) =>
    FieldDef(key, label, FieldType.number, hint: hint);

FieldDef _check(String key, String label) =>
    FieldDef(key, label, FieldType.checkbox);

FieldDef _drop(String key, String label, List<String> options) =>
    FieldDef(key, label, FieldType.dropdown, options: options);

FieldDef _list(String key, String label, {int? maxItems, String? hint}) =>
    FieldDef(key, label, FieldType.list, maxItems: maxItems, hint: hint);

class Marketplaces {
  Marketplaces._();

  static final Marketplace ebay = Marketplace(
    id: 'ebay',
    name: 'eBay',
    entries: <Entry>[
      Entry.shared('Item title', SharedKey.title),
      Entry.own(_text('ebay.subtitle', 'Subtitle', maxLength: 55)),
      Entry.shared('Item category', SharedKey.category, overridable: true),
      Entry.own(_multi('ebay.item_specifics', 'Item specifics',
          hint: 'One per line, e.g. Series Title: Scott Pilgrim')),
      Entry.shared('Item condition', SharedKey.condition, overridable: true),
      Entry.own(_multi('ebay.condition_description', 'Condition description',
          maxLength: 1000)),
      Entry.shared('Description', SharedKey.description),
      Entry.own(_drop('ebay.format', 'Format', ['Buy It Now', 'Auction'])),
      Entry.shared('Item price', SharedKey.price),
      Entry.own(_check('ebay.require_immediate_payment',
          'Require immediate payment when buyer uses Buy It Now')),
      Entry.own(_num('ebay.quantity', 'Quantity')),
      Entry.own(_check('ebay.allow_offers', 'Allow offers')),
      Entry.own(_num('ebay.minimum_offer', 'Minimum offer')),
      Entry.own(_num('ebay.auto_accept', 'Auto accept')),
      Entry.own(_text('ebay.schedule', 'Schedule your listing',
          hint: 'Start date and time; blank = list immediately')),
      Entry.own(_text('ebay.shipping_method', 'Shipping method',
          hint: 'e.g. Standard shipping: Small to medium items')),
      Entry.own(_drop('ebay.units', 'Package measurement units',
          ['Metric (kg., g., cm.)', 'Imperial (lb., oz., in.)'])),
      Entry.own(_text('ebay.weight', 'Package weight', hint: 'e.g. 1 kg 200 g')),
      Entry.own(_text('ebay.dimensions', 'Package dimensions',
          hint: 'Length x width x height')),
      Entry.own(_text('ebay.cost_type', 'Domestic shipping cost type',
          hint: 'e.g. Flat: Same cost to all buyers')),
      Entry.own(_text('ebay.service', 'Primary shipping service',
          hint: 'e.g. UPS Standard Canada')),
      Entry.own(_num('ebay.buyer_pays', 'Buyer pays (shipping)')),
      Entry.own(_check('ebay.free_shipping', 'Offer free shipping')),
      Entry.own(_check('ebay.local_pickup', 'Add local pickup')),
      Entry.own(_text('ebay.excluded_locations', 'Excluded locations')),
      Entry.own(_text('ebay.country_of_origin', 'Country of origin')),
    ],
  );

  static final Marketplace kijiji = Marketplace(
    id: 'kijiji',
    name: 'Kijiji',
    entries: <Entry>[
      Entry.shared('Category', SharedKey.category, overridable: true),
      Entry.own(_drop('kijiji.ad_type', 'Ad Type',
          ["I'm offering", 'I want to find'])),
      Entry.own(_drop('kijiji.for_sale_by', 'For Sale By', ['Owner', 'Business'])),
      Entry.own(_check('kijiji.deliver', 'Willing to drop-off / deliver')),
      Entry.own(_check('kijiji.ship', 'Willing to ship the item')),
      Entry.own(_check('kijiji.curbside', 'Offer curbside pick up')),
      Entry.own(_check('kijiji.cashless', 'Offer cashless payment')),
      Entry.own(_check('kijiji.cash', 'Cash accepted')),
      Entry.shared('Condition', SharedKey.condition, overridable: true),
      Entry.shared('Ad title', SharedKey.title),
      Entry.shared('Description', SharedKey.description),
      Entry.own(_list('kijiji.tags', 'Tags',
          maxItems: 5, hint: 'Up to 5 keywords, separated by commas')),
      Entry.shared('Location', SharedKey.location),
      Entry.own(_drop('kijiji.price_type', 'Price type',
          ['Amount', 'Free', 'Please Contact', 'Swap/Trade'])),
      Entry.shared('Price', SharedKey.price),
      Entry.own(_text('kijiji.phone', 'Phone number')),
    ],
  );

  static final Marketplace facebook = Marketplace(
    id: 'facebook',
    name: 'Facebook Marketplace',
    entries: <Entry>[
      Entry.shared('Title', SharedKey.title),
      Entry.shared('Price', SharedKey.price),
      Entry.shared('Category', SharedKey.category, overridable: true),
      Entry.shared('Condition', SharedKey.condition, overridable: true),
      Entry.shared('Description', SharedKey.description),
      Entry.own(_drop('facebook.availability', 'Availability',
          ['List as Single Item', 'List as In Stock'])),
      Entry.own(_list('facebook.product_tags', 'Product tags',
          maxItems: 20, hint: 'Up to 20, separated by commas')),
      Entry.own(_text('facebook.sku', 'SKU', hint: 'Only visible to you')),
      Entry.shared('Location', SharedKey.location),
      Entry.own(_check('facebook.public_meetup', 'Public meetup')),
      Entry.own(_check('facebook.door_pickup', 'Door pickup')),
      Entry.own(_check('facebook.door_dropoff', 'Door dropoff')),
    ],
  );

  static final Marketplace varagesale = Marketplace(
    id: 'varagesale',
    name: 'VarageSale',
    entries: <Entry>[
      Entry.shared('Title', SharedKey.title),
      Entry.shared('Description', SharedKey.description),
      Entry.shared('Category', SharedKey.category, overridable: true),
      Entry.own(_text('varagesale.subcategory', 'Subcategory')),
      Entry.shared('Price', SharedKey.price),
      Entry.own(_list('varagesale.communities', 'Communities',
          hint: 'Communities to post in, separated by commas')),
      Entry.own(_check('varagesale.looking_for',
          "I'm looking for this item rather than selling it")),
    ],
  );

  static final Marketplace karrot = Marketplace(
    id: 'karrot',
    name: 'Karrot',
    entries: <Entry>[
      Entry.shared('Title', SharedKey.title),
      Entry.shared('Category', SharedKey.category, overridable: true),
      Entry.shared('Condition', SharedKey.condition, overridable: true),
      Entry.shared('Description', SharedKey.description),
      Entry.own(_drop('karrot.listing_type', 'Listing type',
          ['For sale', 'Free', 'Trade'])),
      Entry.shared('Price', SharedKey.price),
      Entry.own(_check('karrot.open_to_offers', 'Open to offers')),
      Entry.own(_check('karrot.shipping', 'Shipping')),
      Entry.shared('Where to meet', SharedKey.location),
    ],
  );

  static final Marketplace poshmark = Marketplace(
    id: 'poshmark',
    name: 'Poshmark',
    entries: <Entry>[
      Entry.shared('Title', SharedKey.title),
      Entry.shared('Description', SharedKey.description),
      Entry.shared('Category', SharedKey.category, overridable: true),
      Entry.own(_text('poshmark.subcategory', 'Subcategory')),
      Entry.own(_drop('poshmark.quantity_type', 'Quantity',
          ['Single Item', 'Multi Item'])),
      Entry.own(_num('poshmark.quantity', 'Multi item quantity')),
      Entry.own(_text('poshmark.size', 'Size')),
      Entry.shared('Condition', SharedKey.condition, overridable: true),
      Entry.own(_text('poshmark.brand', 'Brand')),
      Entry.own(_list('poshmark.colors', 'Color',
          maxItems: 2, hint: 'Up to 2, separated by commas')),
      Entry.own(_list('poshmark.style_tags', 'Style Tags',
          maxItems: 3, hint: 'Up to 3, separated by commas')),
      Entry.shared('Listing Price', SharedKey.price),
      Entry.own(_text('poshmark.discounted_shipping', 'Discounted Shipping')),
      Entry.own(_text('poshmark.availability', 'Availability',
          hint: 'e.g. For Sale')),
    ],
  );

  static final Marketplace depop = Marketplace(
    id: 'depop',
    name: 'Depop',
    entries: <Entry>[
      // Depop has no title field: title + description + hashtags in one box.
      Entry.computed('Description', depopDescription),
      Entry.shared('Category', SharedKey.category, overridable: true),
      Entry.own(_text('depop.brand', 'Brand')),
      Entry.shared('Condition', SharedKey.condition, overridable: true),
      Entry.own(_list('depop.colors', 'Color',
          maxItems: 2, hint: 'Up to 2, separated by commas')),
      Entry.own(_text('depop.size', 'Size')),
      Entry.own(_list('depop.source', 'Source',
          maxItems: 2, hint: 'What kind of item is this? Up to 2')),
      Entry.own(_list('depop.age', 'Age',
          maxItems: 1, hint: 'When was it made? Up to 1')),
      Entry.own(_list('depop.style', 'Style',
          maxItems: 3, hint: 'Up to 3, separated by commas')),
      Entry.shared('Item price', SharedKey.price),
      Entry.own(_text('depop.ship_country', 'Shipping from: Country')),
      Entry.own(_text('depop.ship_city', 'Shipping from: City')),
      Entry.own(_num('depop.shipping_price', 'Shipping price')),
    ],
    formOnly: <FieldDef>[
      _text('depop.hashtags', 'Hashtags',
          hint: 'Up to 5, added to the end of the Depop description'),
    ],
  );

  static final List<Marketplace> all = <Marketplace>[
    ebay,
    kijiji,
    facebook,
    varagesale,
    karrot,
    poshmark,
    depop,
  ];

  static Marketplace byId(String id) =>
      all.firstWhere((m) => m.id == id, orElse: () => throw ArgumentError(id));
}
