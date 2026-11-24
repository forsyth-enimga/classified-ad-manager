import 'dart:convert';

import '../ad.dart';
import '../dates.dart';
import '../marketplaces.dart';
import 'html_utils.dart';
import 'providers.dart';

/// The result of reading a listing page.
class ParsedListing {
  ParsedListing(this.ad, this.marketplace, this.sourceUrl, this.missing);

  /// An unsaved ad (id null), already marked as posted on [marketplace].
  final Ad ad;
  final Marketplace marketplace;

  /// Clean URL of the live listing (no query string), if known.
  final String? sourceUrl;

  /// Mandatory fields the page did not provide (the user must fill them in).
  final List<String> missing;
}

/// Mutable scratch space while a page is read.
class _Draft {
  String title = '';
  String description = '';
  double? price;
  String category = '';
  String condition = '';
  String location = '';
  final Map<String, String> extra = <String, String>{};

  /// Listing URL found inside the page data (used when no URL was given).
  String? sourceUrl;

  void put(String key, String? value) {
    final v = (value ?? '').trim();
    if (v.isNotEmpty) extra[key] = v;
  }
}

/// Words that show a page is a block / bot-check page rather than a listing.
final RegExp _blockPattern = RegExp(
  r'captcha|access denied|are you a (human|robot)|unusual traffic|just a moment|verify you are human|px-captcha|request blocked',
  caseSensitive: false,
);

/// Words that show a login wall.
final RegExp _loginPattern = RegExp(
  r'id="login_form"|log in to (continue|facebook)|you must log in|please log in|sign in to continue|login_popup',
  caseSensitive: false,
);

bool looksBlocked(String html) =>
    html.length < 20000 && _blockPattern.hasMatch(html);

bool looksLikeLoginWall(String html) => _loginPattern.hasMatch(html);

/// Works out which provider a page belongs to from its own address markers
/// (canonical link, og:url, JSON-LD url). Used by "paste page source".
Marketplace? detectProviderFromSource(String html) {
  final candidates = <String>[];
  final canonical = RegExp(
    r'''<link[^>]+rel=["']canonical["'][^>]*href=["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(html);
  if (canonical != null) candidates.add(decodeEntities(canonical.group(1)!));
  final ogUrl = metaContent(html, 'og:url');
  if (ogUrl != null) candidates.add(ogUrl);
  for (final ld in jsonLdBlocks(html)) {
    if (ld['url'] is String) candidates.add(ld['url'] as String);
    final offers = ld['offers'];
    if (offers is Map && offers['url'] is String) {
      candidates.add(offers['url'] as String);
    }
  }
  for (final c in candidates) {
    final u = Uri.tryParse(c);
    if (u == null) continue;
    final p = providerForUrl(u);
    if (p != null) return p;
  }
  // Facebook pages carry no canonical link: use their own markers.
  if (RegExp(r'<html[^>]*\sid="facebook"').hasMatch(html) ||
      html.contains(r'"share_uri":"https:\/\/www.facebook.com\/marketplace')) {
    return Marketplaces.facebook;
  }
  return null;
}

/// Best-effort listing URL from the page itself (for pasted source).
String? detectListingUrl(String html) {
  final canonical = RegExp(
    r'''<link[^>]+rel=["']canonical["'][^>]*href=["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(html);
  if (canonical != null) return cleanUrl(decodeEntities(canonical.group(1)!));
  final og = metaContent(html, 'og:url');
  if (og != null) return cleanUrl(og);
  for (final ld in jsonLdBlocks(html)) {
    if (ldIsType(ld, 'Product')) {
      final offers = ld['offers'];
      if (offers is Map && offers['url'] is String) {
        return cleanUrl(offers['url'] as String);
      }
      if (ld['url'] is String) return cleanUrl(ld['url'] as String);
    }
  }
  return null;
}

/// scheme://host/path, without query or fragment.
String cleanUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return url.trim();
  return Uri(scheme: u.scheme, host: u.host, path: u.path).toString();
}

/// For eBay: the separate page that holds the seller's description.
String? ebayDescriptionUrl(String html) {
  final m = RegExp(
    r'''<iframe[^>]*id=["']?desc_ifr["']?[^>]*\ssrc=["']?([^\s"'>]+)''',
    caseSensitive: false,
  ).firstMatch(html);
  if (m == null) return null;
  return decodeEntities(m.group(1)!);
}

/// Reads a listing page for [marketplace]. Throws [ImportException] when the
/// page holds no listing (login wall, block page, or unrecognised layout).
///
/// [ebayDescriptionHtml] is the body of eBay's separate description page.
ParsedListing parseListing(
  Marketplace marketplace,
  String html, {
  Uri? url,
  String? ebayDescriptionHtml,
  DateTime? today,
}) {
  final d = _Draft();
  final lds = jsonLdBlocks(html);
  final product = lds.cast<Map<String, dynamic>?>().firstWhere(
        (m) => m != null && ldIsType(m, 'Product'),
        orElse: () => null,
      );

  // Generic base: schema.org Product, then Open Graph.
  if (product != null) _fromProduct(d, product);
  if (d.title.isEmpty) {
    final og = metaContent(html, 'og:title');
    if (og != null) d.title = og.replaceAll(RegExp(r'\s*\|\s*[^|]+$'), '').trim();
  }
  d.price ??= parseNumber(
      metaContent(html, 'product:price:amount') ?? metaContent(html, 'og:price:amount'));

  // Platform-specific details.
  switch (marketplace.id) {
    case 'karrot':
      _karrot(d, html, lds);
    case 'varagesale':
      _varagesale(d, html);
    case 'kijiji':
      _kijiji(d, html, lds);
    case 'poshmark':
      _poshmark(d, html, product);
    case 'ebay':
      _ebay(d, html, lds, product, ebayDescriptionHtml);
    case 'depop':
      _depop(d, html, product);
    case 'facebook':
      _facebook(d, html, url);
  }

  if (d.title.isEmpty && d.price == null) {
    if (looksLikeLoginWall(html)) {
      throw ImportException(
        ImportErrorKind.loginRequired,
        'This page needs you to log in, so the listing could not be read.',
      );
    }
    if (marketplace.id == 'facebook' && !looksBlocked(html)) {
      throw ImportException(
        ImportErrorKind.loginRequired,
        'Facebook did not provide the listing details; Marketplace listings usually need you to log in. Open the listing in your browser while logged in, copy the page source, and use "Import from pasted page source".',
      );
    }
    if (looksBlocked(html)) {
      throw ImportException(
        ImportErrorKind.blocked,
        '${marketplace.name} blocked the request (bot check). Open the listing in your browser, copy the page source, and use "Import from pasted page source".',
      );
    }
    throw ImportException(
      ImportErrorKind.noListingData,
      'No listing details were found on that page. It may have been removed, or ${marketplace.name} changed its layout.',
    );
  }

  final ad = Ad(
    title: d.title,
    description: d.description,
    price: d.price,
    category: d.category,
    condition: d.condition,
    location: d.location,
  );
  ad.extra.addAll(d.extra);

  final listingUrl = url != null
      ? cleanUrl(url.toString())
      : (d.sourceUrl != null ? cleanUrl(d.sourceUrl!) : detectListingUrl(html));
  if (listingUrl != null && listingUrl.isNotEmpty) {
    ad.extra['${marketplace.id}.listing_url'] = listingUrl;
  }
  ad.posted[marketplace.id] = true;
  ad.postedDate[marketplace.id] = fmtDate(today ?? DateTime.now());

  final missing = <String>[
    if (ad.title.trim().isEmpty) 'title',
    if (ad.description.trim().isEmpty) 'description',
    if (ad.price == null) 'price',
    if (ad.category.trim().isEmpty) 'category',
  ];
  return ParsedListing(ad, marketplace, listingUrl, missing);
}

// ---------------------------------------------------------------------------
// Generic schema.org Product
// ---------------------------------------------------------------------------

void _fromProduct(_Draft d, Map<String, dynamic> p) {
  d.title = decodeEntities((p['name'] ?? '').toString()).trim();
  d.description = decodeEntities((p['description'] ?? '').toString())
      .replaceAll('\r\n', '\n')
      .trim();
  final offers = p['offers'];
  final offer = offers is List && offers.isNotEmpty ? offers.first : offers;
  if (offer is Map) {
    d.price = parseNumber(offer['price'] ?? offer['lowPrice']);
    d.condition = _schemaCondition((offer['itemCondition'] ?? '').toString());
  }
  final category = p['category'];
  if (category is String && category.trim().isNotEmpty) {
    d.category = decodeEntities(category).split(RegExp(r'[<>]')).map((s) => s.trim()).where((s) => s.isNotEmpty).join(' > ');
  }
}

String _schemaCondition(String url) {
  if (url.endsWith('NewCondition')) return 'New';
  if (url.endsWith('UsedCondition')) return 'Used';
  if (url.endsWith('RefurbishedCondition')) return 'Refurbished';
  if (url.endsWith('DamagedCondition')) return 'For parts or not working';
  return '';
}

/// Names from a BreadcrumbList. [drop] filters out unwanted crumbs.
List<String> _breadcrumbs(List<Map<String, dynamic>> lds) {
  for (final ld in lds) {
    if (!ldIsType(ld, 'BreadcrumbList')) continue;
    final items = ld['itemListElement'];
    if (items is! List) continue;
    final names = <String>[];
    for (final it in items) {
      if (it is! Map) continue;
      var name = it['name'];
      final inner = it['item'];
      if (name == null && inner is Map) name = inner['name'];
      if (name != null) names.add(decodeEntities(name.toString()).trim());
    }
    return names;
  }
  return <String>[];
}

// ---------------------------------------------------------------------------
// Karrot: data is embedded as Remix loader state.
// ---------------------------------------------------------------------------

void _karrot(_Draft d, String html, List<Map<String, dynamic>> lds) {
  Map<String, dynamic>? article;
  final m = RegExp(r'window\.__remixContext\s*=\s*(\{.*?\});\s*</script>', dotAll: true)
      .firstMatch(html);
  if (m != null) {
    try {
      final j = jsonDecode(m.group(1)!);
      final loader = j['state']['loaderData'];
      if (loader is Map) {
        for (final v in loader.values) {
          if (v is Map && v['article'] is Map) {
            article = Map<String, dynamic>.from(v['article'] as Map);
            break;
          }
        }
      }
    } catch (_) {
      article = null;
    }
  }

  if (article != null) {
    if ((article['title'] ?? '').toString().isNotEmpty) {
      d.title = (article['title']).toString().trim();
    }
    if ((article['content'] ?? '').toString().isNotEmpty) {
      d.description = (article['content']).toString().replaceAll('\r\n', '\n').trim();
    }
    d.price = parseNumber(article['price']) ?? d.price;
    final props = article['articlePropertyContents'];
    if (props is List) {
      for (final p in props) {
        if (p is! Map) continue;
        final title = (p['title'] ?? '').toString().toLowerCase();
        final content = (p['content'] ?? '').toString().trim();
        if (title == 'condition' && content.isNotEmpty) d.condition = content;
      }
    }
    final trading = article['tradingLocation'];
    if (trading is Map && trading['name'] != null) {
      d.location = trading['name'].toString().trim();
    }
    final lt = (article['listingType'] ?? '').toString().toLowerCase();
    if (lt == 'sell') {
      d.extra['karrot.listing_type'] = 'For sale';
    } else if (lt.contains('free') || lt.contains('give')) {
      d.extra['karrot.listing_type'] = 'Free';
    } else if (lt.contains('trade') || lt.contains('swap') || lt.contains('exchange')) {
      d.extra['karrot.listing_type'] = 'Trade';
    }
    if (article['offerable'] == true) d.extra['karrot.open_to_offers'] = 'true';
  }

  // Category trail from the breadcrumb: drop "Buy and sell" and the item itself.
  final crumbs = _breadcrumbs(lds);
  if (crumbs.length > 2) {
    d.category = crumbs.sublist(1, crumbs.length - 1).join(' > ');
  }
}

// ---------------------------------------------------------------------------
// VarageSale: server-rendered HTML.
// ---------------------------------------------------------------------------

void _varagesale(_Draft d, String html) {
  final cats = RegExp(
    r'''class="breadcrumb-element"[^>]*href="[^"]*/c/[^"]*"[^>]*>(.*?)</a>''',
    dotAll: true,
  ).allMatches(html).map((m) => inlineText(m.group(1)!)).where((t) => t.isNotEmpty).toList();
  // The last crumb is often repeated; keep the order but remove adjacent duplicates.
  final trail = <String>[];
  for (final c in cats) {
    if (trail.isEmpty || trail.last != c) trail.add(c);
  }
  if (trail.isNotEmpty) d.category = trail.join(' > ');

  final loc = RegExp(r'Seller can meet near</span>.*?<strong>(.*?)</strong>', dotAll: true)
      .firstMatch(html);
  if (loc != null) d.location = inlineText(loc.group(1)!);

  final comm = RegExp(r'following communities</span>(.*?)</p>', dotAll: true).firstMatch(html);
  if (comm != null) {
    final names = RegExp(r'<a\b[^>]*>(.*?)</a>', dotAll: true)
        .allMatches(comm.group(1)!)
        .map((m) => inlineText(m.group(1)!))
        .where((t) => t.isNotEmpty)
        .toList();
    d.put('varagesale.communities', names.join(', '));
  }
}

// ---------------------------------------------------------------------------
// Facebook Marketplace: listing object inside the page's embedded JSON.
// The page names no category (only a numeric id), so category stays blank.
// ---------------------------------------------------------------------------

Map<String, dynamic>? _facebookListing(String html, String? wantedId) {
  Map<String, dynamic>? fallback;
  Map<String, dynamic>? found;

  void walk(dynamic o) {
    if (found != null) return;
    if (o is Map) {
      if (o.containsKey('marketplace_listing_title') && o.containsKey('redacted_description')) {
        final m = Map<String, dynamic>.from(o);
        if (wantedId == null || m['id']?.toString() == wantedId) {
          found = m;
          return;
        }
        fallback ??= m;
      }
      for (final v in o.values) {
        walk(v);
      }
    } else if (o is List) {
      for (final v in o) {
        walk(v);
      }
    }
  }

  final re = RegExp(r'<script[^>]*type="application/json"[^>]*>(.*?)</script>', dotAll: true);
  for (final m in re.allMatches(html)) {
    final body = m.group(1)!;
    if (!body.contains('redacted_description')) continue;
    try {
      walk(jsonDecode(body));
    } catch (_) {
      // not the script we want
    }
    if (found != null) break;
  }
  return found ?? fallback;
}

void _facebook(_Draft d, String html, Uri? url) {
  final idMatch = url == null ? null : RegExp(r'/marketplace/item/(\d+)').firstMatch(url.path);
  final l = _facebookListing(html, idMatch?.group(1));
  if (l == null) return;

  // Titles can contain line breaks; the form wants one line.
  d.title = (l['marketplace_listing_title'] ?? '').toString().replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
  final desc = l['redacted_description'];
  if (desc is Map && desc['text'] != null) {
    d.description = desc['text'].toString().replaceAll('\r\n', '\n').trim();
  }
  final price = l['listing_price'];
  if (price is Map) d.price = parseNumber(price['amount']);
  final loc = l['location_text'];
  if (loc is Map && loc['text'] != null) d.location = loc['text'].toString().trim();

  final attrs = l['attribute_data'];
  if (attrs is List) {
    for (final a in attrs) {
      if (a is Map && (a['attribute_name'] ?? '').toString().toLowerCase() == 'condition') {
        d.condition = (a['label'] ?? a['value'] ?? '').toString().trim();
      }
    }
  }

  final inv = (l['listing_inventory_type'] ?? '').toString();
  if (inv.isNotEmpty) {
    d.extra['facebook.availability'] =
        inv == 'SINGLE_QUANTITY' ? 'List as Single Item' : 'List as In Stock';
  }
  final tags = l['marketplace_hashtags'];
  if (tags is Map && tags['nodes'] is List) {
    final names = (tags['nodes'] as List)
        .whereType<Map>()
        .map((n) => (n['tag_name'] ?? '').toString().trim())
        .where((t) => t.isNotEmpty)
        .take(20)
        .toList();
    d.put('facebook.product_tags', names.join(', '));
  }
  if (l['share_uri'] is String) d.sourceUrl = l['share_uri'] as String;
}

// ---------------------------------------------------------------------------
// Kijiji: Apollo state inside __NEXT_DATA__.
// ---------------------------------------------------------------------------

void _kijiji(_Draft d, String html, List<Map<String, dynamic>> lds) {
  Map<String, dynamic>? listing;
  final m = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true).firstMatch(html);
  if (m != null) {
    try {
      final j = jsonDecode(m.group(1)!);
      final apollo = j['props']['pageProps']['__APOLLO_STATE__'];
      if (apollo is Map) {
        for (final e in apollo.entries) {
          if (e.key.toString().startsWith('StandardListing:') && e.value is Map) {
            listing = Map<String, dynamic>.from(e.value as Map);
            break;
          }
        }
      }
    } catch (_) {
      listing = null;
    }
  }

  var city = '';
  if (listing != null) {
    if ((listing['title'] ?? '').toString().isNotEmpty && d.title.isEmpty) {
      d.title = listing['title'].toString().trim();
    }
    if (d.description.isEmpty && listing['description'] != null) {
      d.description = listing['description'].toString().replaceAll('\r\n', '\n').trim();
    }
    final price = listing['price'];
    if (price is Map) {
      if (d.price == null && price['amount'] != null) {
        final cents = parseNumber(price['amount']);
        if (cents != null) d.price = cents / 100;
      }
      final type = (price['type'] ?? '').toString().toUpperCase();
      if (type == 'FIXED' || type == 'AMOUNT') {
        d.extra['kijiji.price_type'] = 'Amount';
      } else if (type.contains('FREE')) {
        d.extra['kijiji.price_type'] = 'Free';
      } else if (type.contains('CONTACT')) {
        d.extra['kijiji.price_type'] = 'Please Contact';
      } else if (type.contains('SWAP') || type.contains('TRADE')) {
        d.extra['kijiji.price_type'] = 'Swap/Trade';
      }
    }
    final adType = (listing['type'] ?? '').toString().toUpperCase();
    if (adType == 'OFFER') d.extra['kijiji.ad_type'] = "I'm offering";
    if (adType == 'WANTED') d.extra['kijiji.ad_type'] = 'I want to find';

    final loc = listing['location'];
    if (loc is Map) {
      city = (loc['name'] ?? '').toString().trim();
      // Only the city and postal code are imported, never the street address.
      final postal = RegExp(r'[A-Za-z]\d[A-Za-z][ -]?\d[A-Za-z]\d')
          .firstMatch((loc['address'] ?? '').toString());
      final parts = <String>[
        if (city.isNotEmpty) city,
        if (postal != null) postal.group(0)!.toUpperCase(),
      ];
      d.location = parts.join(', ');
    }

    final attrs = listing['attributes'];
    final all = attrs is Map ? attrs['all'] : null;
    if (all is List) {
      for (final a in all) {
        if (a is! Map) continue;
        final name = (a['canonicalName'] ?? '').toString();
        final canon = a['canonicalValues'] is List ? (a['canonicalValues'] as List) : const [];
        final values = a['values'] is List ? (a['values'] as List) : const [];
        final isTrue = canon.contains('true') || values.contains('Yes');
        switch (name) {
          case 'condition':
            if (values.isNotEmpty) d.condition = values.first.toString();
          case 'cashaccepted':
            if (isTrue) d.extra['kijiji.cash'] = 'true';
          case 'cashless':
            if (isTrue) d.extra['kijiji.cashless'] = 'true';
          case 'dropoff':
            if (isTrue) d.extra['kijiji.deliver'] = 'true';
          case 'shipping':
            if (isTrue) d.extra['kijiji.ship'] = 'true';
          case 'curbside':
            if (isTrue) d.extra['kijiji.curbside'] = 'true';
          case 'forsaleby':
            d.extra['kijiji.for_sale_by'] =
                canon.contains('ownr') || values.contains('Owner') ? 'Owner' : 'Business';
        }
      }
    }
  }

  // Category trail from the breadcrumb: drop "Home", the "Ad ID" crumb, and
  // the " for <city>" suffix Kijiji adds to the last category.
  final crumbs = _breadcrumbs(lds)
      .where((c) => c != 'Home' && !c.startsWith('Ad ID'))
      .map((c) => city.isNotEmpty && c.endsWith(' for $city')
          ? c.substring(0, c.length - ' for $city'.length)
          : c)
      .toList();
  if (crumbs.isNotEmpty) d.category = crumbs.join(' > ');
}

// ---------------------------------------------------------------------------
// Poshmark: details table in the server-rendered HTML.
// ---------------------------------------------------------------------------

void _poshmark(_Draft d, String html, Map<String, dynamic>? product) {
  final rows = <String, List<String>>{};
  final re = RegExp(
    r'<dt class="item-details__key">(.*?)</dt>\s*<dd[^>]*>(.*?)</dd>',
    dotAll: true,
  );
  for (final m in re.allMatches(html)) {
    final key = inlineText(m.group(1)!).toLowerCase();
    final spans = spanTexts(m.group(2)!);
    rows.putIfAbsent(key, () => spans.isNotEmpty ? spans : [inlineText(m.group(2)!)]);
  }
  String first(String k) => (rows[k] ?? const <String>[]).isEmpty ? '' : rows[k]!.first;

  d.put('poshmark.size', first('size'));
  d.put('poshmark.brand', first('brand').isNotEmpty ? first('brand') : _brandName(product));
  final cond = first('condition');
  if (cond.isNotEmpty) d.condition = cond;
  d.put('poshmark.colors', (rows['color'] ?? const <String>[]).join(', '));
  d.put('poshmark.style_tags', (rows['style tags'] ?? const <String>[]).join(', '));
  d.extra['poshmark.quantity_type'] = 'Single Item';
  if (d.category.isEmpty && (rows['category'] ?? const <String>[]).isNotEmpty) {
    d.category = rows['category']!.join(' > ');
  }
}

String _brandName(Map<String, dynamic>? product) {
  final b = product?['brand'];
  if (b is Map && b['name'] != null) return decodeEntities(b['name'].toString()).trim();
  if (b is String) return b.trim();
  return '';
}

// ---------------------------------------------------------------------------
// eBay: item specifics table, JSON-LD shipping, separate description page.
// ---------------------------------------------------------------------------

void _ebay(
  _Draft d,
  String html,
  List<Map<String, dynamic>> lds,
  Map<String, dynamic>? product,
  String? descriptionHtml,
) {
  // Category trail: drop the leading "eBay" crumb.
  final crumbs = _breadcrumbs(lds).where((c) => c != 'eBay').toList();
  if (crumbs.isNotEmpty) d.category = crumbs.join(' > ');

  // Item specifics table.
  final start = html.indexOf('ux-layout-section--features');
  final specifics = <String>[];
  if (start >= 0) {
    var end = html.indexOf('ux-layout-section--', start + 30);
    if (end < 0 || end - start > 60000) end = start + 60000 > html.length ? html.length : start + 60000;
    final block = html.substring(start, end);
    final re = RegExp(
      r'ux-labels-values__labels-content"?>(.*?)</dt>\s*<dd class="?ux-labels-values__values"?>(.*?)</dd>',
      dotAll: true,
    );
    for (final m in re.allMatches(block)) {
      final label = inlineText(m.group(1)!).replaceAll(RegExp(r':\s*$'), '');
      var value = inlineText(m.group(2)!);
      if (label.isEmpty || value.isEmpty) continue;
      if (label.toLowerCase() == 'condition') {
        // "New with tags: This item is brand new..." -> "New with tags"
        d.condition = value.split(':').first.trim();
        continue;
      }
      final lower = label.toLowerCase();
      if (lower.startsWith('country of origin') || (lower.startsWith('country') && lower.contains('manufactur'))) {
        d.put('ebay.country_of_origin', value);
      }
      value = value.replaceAll(RegExp(r'\s*Read more about.*$'), '');
      specifics.add('$label: $value');
    }
  }
  d.put('ebay.item_specifics', specifics.join('\n'));

  // Location ("Located in: Calgary, Alberta, Canada").
  final loc = RegExp(r'Located in:\s*([^<]+)').firstMatch(html);
  if (loc != null) d.location = decodeEntities(loc.group(1)!).trim();

  // Buy It Now vs auction.
  if (html.contains('x-bin-price')) {
    d.extra['ebay.format'] = 'Buy It Now';
  } else if (html.contains('x-bid-price')) {
    d.extra['ebay.format'] = 'Auction';
  }

  // Shipping cost from JSON-LD.
  final offers = product?['offers'];
  final offer = offers is List && offers.isNotEmpty ? offers.first : offers;
  if (offer is Map) {
    final sd = offer['shippingDetails'];
    final detail = sd is List && sd.isNotEmpty ? sd.first : sd;
    if (detail is Map && detail['shippingRate'] is Map) {
      final rate = parseNumber((detail['shippingRate'] as Map)['value']);
      if (rate != null) {
        if (rate == 0) {
          d.extra['ebay.free_shipping'] = 'true';
        } else {
          d.extra['ebay.buyer_pays'] = money(rate);
        }
      }
    }
  }

  // The seller's description lives on a separate page.
  if (descriptionHtml != null) {
    final text = htmlToText(descriptionHtml);
    if (text.isNotEmpty) d.description = text;
  } else {
    d.description = '';
  }
}

// ---------------------------------------------------------------------------
// Depop: JSON-LD for the basics, embedded product data for attributes.
// Depop has no title field: the first paragraph of its description is the
// title, and trailing #hashtags are the hashtags (the reverse of our export).
// ---------------------------------------------------------------------------

void _depop(_Draft d, String html, Map<String, dynamic>? product) {
  d.put('depop.brand', _brandName(product));
  // Split "title\n\ndescription\n\n#tags" back into its parts.
  final paragraphs = d.description
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (paragraphs.isNotEmpty) {
    d.title = paragraphs.removeAt(0);
    if (paragraphs.isNotEmpty && RegExp(r'^(#\S+\s*)+$').hasMatch(paragraphs.last)) {
      d.put('depop.hashtags', paragraphs.removeLast());
    }
    d.description = paragraphs.join('\n\n');
  }

  // Embedded (escaped) product data: unescape, then find this product by its
  // description text so the "similar items" data is not mixed in.
  final text = html.replaceAll(r'\"', '"').replaceAll(r'\u0026', '&');
  final firstWords = d.title.isEmpty
      ? ''
      : (d.title.length > 24 ? d.title.substring(0, 24) : d.title);
  var anchor = firstWords.isEmpty ? -1 : text.indexOf('"description":"$firstWords');
  if (anchor < 0 && firstWords.isNotEmpty) {
    anchor = text.indexOf('"description":"${firstWords.substring(0, firstWords.length > 12 ? 12 : firstWords.length)}');
  }
  if (anchor >= 0) {
    final before = text.substring(anchor - 2500 < 0 ? 0 : anchor - 2500, anchor);
    final after = text.substring(anchor, anchor + 8000 > text.length ? text.length : anchor + 8000);

    final attrsAt = before.lastIndexOf('"attributes":{');
    if (attrsAt >= 0) {
      final obj = _balancedObject(before, attrsAt + '"attributes":'.length);
      if (obj != null) {
        try {
          final a = jsonDecode(obj) as Map<String, dynamic>;
          d.put('depop.colors', _listText(a['colour']));
          d.put('depop.style', _listText(a['style']));
          d.put('depop.source', _listText(a['source']));
          d.put('depop.age', _listText(a['age']));
          final gender = (a['gender'] ?? '').toString();
          final group = (a['group'] ?? '').toString();
          final type = (a['product_type'] ?? '').toString();
          if (d.category.isEmpty && (group.isNotEmpty || type.isNotEmpty)) {
            d.category = <String>[
              if (gender == 'male') 'Menswear' else if (gender == 'female') 'Womenswear' else if (gender.isNotEmpty) 'Unisex',
              if (group.isNotEmpty) _cap(group),
              if (type.isNotEmpty) _cap(type),
            ].join(' > ');
          }
        } catch (_) {
          // attributes are optional
        }
      }
    }
    final cond = RegExp(r'"condition_name":"([^"]+)"').allMatches(before).lastOrNull;
    if (cond != null) d.condition = cond.group(1)!;

    final loc = RegExp(r'"location":"([^"]+)"').firstMatch(after);
    if (loc != null) {
      final parts = loc.group(1)!.split(',').map((s) => s.trim()).toList();
      if (parts.isNotEmpty) d.put('depop.ship_city', parts.first);
      if (parts.length > 1) d.put('depop.ship_country', parts.last);
      if (d.location.isEmpty) d.location = loc.group(1)!;
    }
  }
  // Only one national shipping cost is embedded (the product's own).
  final ship = RegExp(r'national_shipping_cost[\\"]*:\{[\\"]*total_price[\\"]*:[\\"]*([\d.]+)')
      .firstMatch(html);
  if (ship != null) d.put('depop.shipping_price', ship.group(1));

  // Size and condition as shown on the page.
  final primary = html.indexOf('data-testid="productPrimaryAttributes"');
  if (primary >= 0) {
    final seg = inlineText(html.substring(primary, primary + 1500 > html.length ? html.length : primary + 1500));
    final size = RegExp(r'Size ([^•]+?)(?: •|$)').firstMatch(seg);
    if (size != null) d.put('depop.size', size.group(1));
  }
}

String _listText(dynamic v) {
  if (v is List) return v.map((e) => _cap(e.toString())).join(', ');
  return '';
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The JSON object starting at [from] (which must point at `{`), found by
/// brace matching while respecting strings.
String? _balancedObject(String s, int from) {
  if (from >= s.length || s[from] != '{') return null;
  var depth = 0;
  var inString = false;
  for (var i = from; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inString = false;
      }
    } else if (c == '"') {
      inString = true;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return s.substring(from, i + 1);
    }
  }
  return null;
}
