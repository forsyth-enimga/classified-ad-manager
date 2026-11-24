// ignore_for_file: avoid_relative_lib_imports
// Plain-Dart checks of the core logic (no packages needed):
//   dart run tool/self_check.dart [optional-zip-output-path]
import 'dart:io';

import '../lib/core/ad.dart';
import '../lib/core/ad_filter.dart';
import '../lib/core/exporter.dart';
import '../lib/core/importing/listing_parser.dart';
import '../lib/core/importing/providers.dart';
import '../lib/core/marketplaces.dart';
import '../lib/core/validation.dart';

var _failed = 0;

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    stdout.writeln('PASS  $name');
  } else {
    _failed++;
    stdout.writeln('FAIL  $name${detail == null ? '' : '\n      $detail'}');
  }
}

Ad sample() => Ad(
      title: 'Samsung 23',
      description: 'Line one\nLine two',
      price: 450,
      category: 'Cell Phones',
      condition: 'Good',
      location: 'Calgary, AB T3P 1S7',
    );

/// Runs [body] and returns the ImportErrorKind it throws, or null.
ImportErrorKind? importError(void Function() body) {
  try {
    body();
    return null;
  } on ImportException catch (e) {
    return e.kind;
  }
}

String? _argValue(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}

void main(List<String> args) {
  final zipOut = _argValue(args, 'zip') ?? args.where((a) => !a.startsWith('--')).firstOrNull;
  final fixturesDir = _argValue(args, 'fixtures');
  // --- export format -------------------------------------------------------
  final ad = sample();
  final text = buildExportText(Marketplaces.karrot, ad);
  check('karrot starts with Title/Samsung 23', text.startsWith('Title\nSamsung 23\n'), text);
  check('multi-line description keeps line breaks',
      text.contains('Description\nLine one\nLine two\n'), text);
  check('price has two decimals', text.contains('Price\n450.00\n'), text);
  check('karrot checkbox defaults to No', text.contains('Open to offers\nNo\n'), text);
  check('karrot location uses its own label',
      text.contains('Where to meet\nCalgary, AB T3P 1S7\n'), text);

  final kijiji = buildExportText(Marketplaces.kijiji, ad);
  check('kijiji has no eBay-only field', !kijiji.contains('Subtitle'));
  check('kijiji has its own fields',
      kijiji.contains('Ad title\nSamsung 23\n') && kijiji.contains('Tags\n'));

  // Overrides
  ad.extra['ebay.category'] = 'Collectibles > Comics';
  check('category override is used',
      buildExportText(Marketplaces.ebay, ad).contains('Item category\nCollectibles > Comics\n'));
  check('override does not leak to other platforms',
      buildExportText(Marketplaces.kijiji, ad).contains('Category\nCell Phones\n'));

  // List + checkbox formatting
  ad.extra['kijiji.tags'] = ' phone , samsung,\nandroid ';
  ad.extra['kijiji.ship'] = 'true';
  final k2 = buildExportText(Marketplaces.kijiji, ad);
  check('list fields are comma joined', k2.contains('Tags\nphone, samsung, android\n'), k2);
  check('checked box exports Yes', k2.contains('Willing to ship the item\nYes\n'), k2);

  // --- Depop ---------------------------------------------------------------
  ad.extra['depop.hashtags'] = 'vintage, #nike  streetwear';
  final depop = buildExportText(Marketplaces.depop, ad);
  check(
      'depop description = title + description + hashtags',
      depop.startsWith(
          'Description\nSamsung 23\n\nLine one\nLine two\n\n#vintage #nike #streetwear\n'),
      depop);
  check('depop has no separate title entry', !depop.contains('\nTitle\n'));
  check('depop clean ad has no warnings', exportWarnings(Marketplaces.depop, ad).isEmpty);
  ad.extra['depop.hashtags'] = '#a #b #c #d #e #f';
  check('depop warns on 6 hashtags',
      exportWarnings(Marketplaces.depop, ad).any((w) => w.contains('hashtags')));
  ad.extra['depop.hashtags'] = '';
  ad.description = 'contact me me@example.com';
  check('depop warns on email',
      exportWarnings(Marketplaces.depop, ad).any((w) => w.contains('email')));
  ad.description = 'x' * 500;
  ad.title = 'y' * 80;
  ad.extra['depop.hashtags'] = ('#tag ' * 5).trim();
  check('depop: 80 + 500 + 5 hashtags fits in 1000',
      depopDescription(ad).length <= kDepopTextMax && exportWarnings(Marketplaces.depop, ad).isEmpty);
  ad.description = 'x' * 1000;
  check('depop: a 1000-char description warns (title + description > 1000)',
      exportWarnings(Marketplaces.depop, ad).any((w) => w.contains('allows 1000')));
  ad.description = 'x' * 501;
  check('poshmark warns above 500 characters',
      exportWarnings(Marketplaces.poshmark, ad).any((w) => w.contains('Poshmark')));
  ad.description = 'x' * 500;
  check('poshmark does not warn at 500', exportWarnings(Marketplaces.poshmark, ad).isEmpty);

  // --- validation ----------------------------------------------------------
  final errs = validateAd(Ad());
  check(
      'empty ad fails title/description/price/category',
      errs.containsKey('title') &&
          errs.containsKey('description') &&
          errs.containsKey('price') &&
          errs.containsKey('category'));
  check('valid ad passes', validateAd(sample()).isEmpty, validateAd(sample()).toString());
  check('title 81 chars fails', validateAd(sample()..title = 'a' * 81).containsKey('title'));
  check('title 80 chars passes', !validateAd(sample()..title = 'a' * 80).containsKey('title'));
  check('description 1001 chars fails',
      validateAd(sample()..description = 'a' * 1001).containsKey('description'));
  check('description 1000 chars passes',
      !validateAd(sample()..description = 'a' * 1000).containsKey('description'));
  check('sold without platform fails',
      validateAd(sample()..sold = true).containsKey('sold_platform'));
  check('sold with platform passes',
      validateAd(sample()
        ..sold = true
        ..soldPlatform = 'Kijiji').isEmpty);
  check('ebay subtitle 56 chars fails',
      validateAd(sample()..extra['ebay.subtitle'] = 'a' * 56).containsKey('ebay.subtitle'));
  check('poshmark 3 colors fails',
      validateAd(sample()..extra['poshmark.colors'] = 'a,b,c').containsKey('poshmark.colors'));
  check('non-numeric number field fails',
      validateAd(sample()..extra['ebay.quantity'] = 'two').containsKey('ebay.quantity'));
  check('bad date fails',
      validateAd(sample()..relistReminder = '2026-13-40').containsKey('relist_reminder'));

  // --- clone ---------------------------------------------------------------
  final src = sample()
    ..id = 7
    ..sold = true
    ..soldPlatform = 'eBay'
    ..posted['ebay'] = true
    ..title = 'a' * 80;
  final c = src.cloneForNew();
  check('clone has no id and keeps content', c.id == null && c.description == src.description);
  check('clone resets posted/sold', !c.sold && !c.isPosted('ebay'));
  check('clone title still within limit',
      c.title.length <= kTitleMax && c.title.endsWith(' (copy)'));

  // --- filters -------------------------------------------------------------
  final a1 = sample()
    ..title = 'Blue bike'
    ..posted['kijiji'] = true;
  final a2 = sample()
    ..title = 'Red couch'
    ..sold = true;
  final a3 = sample()
    ..title = 'Lamp'
    ..relistReminder = '2026-11-01';
  final ads = [a1, a2, a3];
  final today = DateTime(2026, 11, 20);
  check('search by text', filterAds(ads, query: 'couch').length == 1);
  check('unsold filter', filterAds(ads, status: StatusFilter.unsold).length == 2);
  check('sold filter', filterAds(ads, status: StatusFilter.sold).length == 1);
  check('relist due filter',
      filterAds(ads, status: StatusFilter.relistDue, today: today).single.title == 'Lamp');
  check('not posted on kijiji',
      filterAds(ads, platformId: 'kijiji', posted: PostedFilter.notPosted).length == 2);
  check('posted anywhere', filterAds(ads, posted: PostedFilter.posted).length == 1);

  // --- names + zip ---------------------------------------------------------
  check('file name', exportFileName(sample(), Marketplaces.kijiji) == 'Samsung-23_kijiji.txt');
  check('slug fallback', slugify('???') == 'ad');
  final zip = buildAllZip(sample());
  check('zip starts with PK', zip[0] == 0x50 && zip[1] == 0x4b);
  if (zipOut != null) {
    File(zipOut).writeAsBytesSync(zip);
    stdout.writeln('wrote $zipOut (${zip.length} bytes)');
  }

  // --- import: provider matching and URL handling ---------------------------
  String? prov(String u) => providerForUrl(Uri.parse(u))?.id;
  check('kijiji.ca matches', prov('https://www.kijiji.ca/v-x/calgary/y/1') == 'kijiji');
  check('ebay.ca / ebay.com / ebay.co.uk match',
      prov('https://www.ebay.ca/itm/1') == 'ebay' &&
          prov('https://ebay.com/itm/1') == 'ebay' &&
          prov('https://www.ebay.co.uk/itm/1') == 'ebay');
  check('ebay.us short link matches', prov('https://ebay.us/abc') == 'ebay');
  check('facebook / fb.me match',
      prov('https://www.facebook.com/marketplace/item/1') == 'facebook' &&
          prov('https://m.facebook.com/marketplace/item/1') == 'facebook' &&
          prov('https://fb.me/x') == 'facebook');
  check('varagesale/karrot/poshmark/depop match',
      prov('https://www.varagesale.com/items/x') == 'varagesale' &&
          prov('https://karrotmarket.com/ca/buy-sell/x/') == 'karrot' &&
          prov('https://poshmark.ca/listing/x') == 'poshmark' &&
          prov('https://poshmark.com/listing/x') == 'poshmark' &&
          prov('https://www.depop.com/products/x/') == 'depop');
  check('look-alike domains do not match',
      prov('https://notkijiji.ca/x') == null &&
          prov('https://kijiji.ca.evil.com/x') == null &&
          prov('https://example.com/x') == null);
  check('bare link gets https', parseUserUrl('kijiji.ca/v-a/b/c/1').scheme == 'https');
  check('empty link is invalid', importError(() => parseUserUrl('  ')) == ImportErrorKind.invalidUrl);
  check('garbage is invalid', importError(() => parseUserUrl('not a url')) == ImportErrorKind.invalidUrl);
  check('listing URLs normalise',
      normalizeListingUrl('https://www.depop.com/products/abc-123/?moduleOrigin=meganav') ==
          normalizeListingUrl('http://depop.com/products/abc-123'));

  // --- import: generic page handling ---------------------------------------
  const ldPage =
      '<html><head><script type="application/ld+json">{"@type":"Product","name":"Tea &amp; Cups","description":"Nice\\r\\nset","offers":{"price":"12.50","itemCondition":"https://schema.org/UsedCondition"}}</script></head></html>';
  final generic = parseListing(Marketplaces.facebook, ldPage,
      url: Uri.parse('https://www.facebook.com/marketplace/item/1?ref=x'), today: DateTime(2026, 11, 22));
  check('generic: entities decoded in title', generic.ad.title == 'Tea & Cups', generic.ad.title);
  check('generic: price and condition', generic.ad.price == 12.5 && generic.ad.condition == 'Used');
  check('generic: marked posted today',
      generic.ad.isPosted('facebook') && generic.ad.postedDate['facebook'] == '2026-11-22');
  check('generic: listing URL stored without query',
      generic.ad.extraValue('facebook.listing_url') == 'https://www.facebook.com/marketplace/item/1');
  check('generic: missing category reported', generic.missing.contains('category'));
  check('login wall -> loginRequired',
      importError(() => parseListing(Marketplaces.facebook, '<html><form id="login_form"></form></html>')) ==
          ImportErrorKind.loginRequired);
  check('facebook page with no listing data -> loginRequired',
      importError(() => parseListing(Marketplaces.facebook, '<html><body>Something went wrong</body></html>')) ==
          ImportErrorKind.loginRequired);
  check('bot check page -> blocked',
      importError(() => parseListing(Marketplaces.kijiji, '<html><title>Access Denied</title></html>')) ==
          ImportErrorKind.blocked);
  check('empty page -> noListingData',
      importError(() => parseListing(Marketplaces.kijiji, '<html><body>hi</body></html>')) ==
          ImportErrorKind.noListingData);
  const depopLd =
      '<script type="application/ld+json">{"@type":"Product","name":"Short...","description":"Title line\\n\\nBody text\\n\\n#a #b","offers":{"price":"9"}}</script>';
  final dp = parseListing(Marketplaces.depop, depopLd);
  check('depop: title/description/hashtags split',
      dp.ad.title == 'Title line' &&
          dp.ad.description == 'Body text' &&
          dp.ad.extraValue('depop.hashtags') == '#a #b',
      '${dp.ad.title} | ${dp.ad.description} | ${dp.ad.extraValue('depop.hashtags')}');
  check('depop import round-trips through export',
      buildExportText(Marketplaces.depop, dp.ad).startsWith('Description\nTitle line\n\nBody text\n\n#a #b\n'));
  final longDesc = parseListing(
      Marketplaces.facebook,
      ldPage.replaceFirst(RegExp(r'"description":"[^"]*"'), '"description":"${'z' * 1200}"'));
  check('over-limit description kept in full and flagged',
      longDesc.ad.description.length == 1200 && validateAd(longDesc.ad).containsKey('description'));
  check('over-limit title kept in full (user must shorten)',
      parseListing(Marketplaces.facebook, ldPage.replaceFirst('Tea &amp; Cups', 'x' * 120)).ad.title.length == 120);

  // --- import: real page sources (only when --fixtures=DIR is given) --------
  if (fixturesDir != null) {
    String read(String n) => File('$fixturesDir/$n').readAsStringSync();
    final kar = parseListing(Marketplaces.karrot, read('KarrotSource.txt'));
    check('karrot fixture', kar.ad.title.startsWith('Gucci') && kar.ad.price == 80 && kar.ad.condition == 'Like new' &&
        kar.ad.category == 'Health & Beauty > Fragrance > Eaux De Parfum' && kar.ad.extraValue('karrot.listing_type') == 'For sale', kar.ad.category);
    final vs = parseListing(Marketplaces.varagesale, read('VaragesaleSource.txt'));
    check('varagesale fixture', vs.ad.title.startsWith('Lululemon') && vs.ad.price == 30 &&
        vs.ad.category == 'Clothing > Women > Active > Small (4-6)' && vs.ad.location == 'Cochrane, AB', vs.ad.category);
    final kj = parseListing(Marketplaces.kijiji, read('KijijiSource.txt'));
    check('kijiji fixture', kj.ad.title == 'Razer Kishi' && kj.ad.price == 20 && kj.ad.condition == 'Used - Fair' &&
        kj.ad.category == 'Buy and Sell > Video Games and Consoles > Other' &&
        kj.ad.extraValue('kijiji.cash') == 'true' && kj.ad.extraValue('kijiji.for_sale_by') == 'Owner', kj.ad.category);
    check('kijiji: street address is not imported', !kj.ad.location.contains('Blvd') && kj.ad.location.startsWith('Calgary'), kj.ad.location);
    final pm = parseListing(Marketplaces.poshmark, read('PoshmarkSource.txt'));
    check('poshmark fixture (price from meta data)', pm.ad.price == 560 && pm.ad.condition == 'Like New' &&
        pm.ad.extraValue('poshmark.brand') == 'Juicy Couture' && pm.ad.extraValue('poshmark.colors') == 'Pink, Black' &&
        pm.ad.category == 'Women > Bags > Shoulder Bags', '${pm.ad.price} ${pm.ad.category}');
    final eb = parseListing(Marketplaces.ebay, read('eBaySource.txt'),
        ebayDescriptionHtml: '<div>Hello<br>World</div>');
    check('ebay fixture', eb.ad.title.startsWith('Ed Hardy') && eb.ad.price == 80 && eb.ad.condition == 'New with tags' &&
        eb.ad.extraValue('ebay.buyer_pays') == '40.00' && eb.ad.extraValue('ebay.item_specifics').contains('Brand: Ed Hardy') &&
        eb.ad.description == 'Hello\nWorld', eb.ad.condition);
    check('ebay without description page leaves it blank',
        parseListing(Marketplaces.ebay, read('eBaySource.txt')).missing.contains('description'));
    final dpFix = parseListing(Marketplaces.depop, read('DepopSource.txt'));
    check('depop fixture', dpFix.ad.title.startsWith('2010s Twilight Bella & Edward') && dpFix.ad.price == 35 &&
        dpFix.ad.extraValue('depop.hashtags').startsWith('#twilight') && dpFix.ad.extraValue('depop.size') == 'L' &&
        dpFix.ad.extraValue('depop.colors') == 'Black', dpFix.ad.title);
    final fb = parseListing(Marketplaces.facebook, read('FacebookSource.txt'));
    check('facebook fixture', fb.ad.title == 'i5 Dell Optiplex 3040 - 16GB RAM - SSD - Windows 11 Pro Computer / Desktop PC' &&
        fb.ad.price == 80 && fb.ad.condition == 'Used - Good' && fb.ad.location == 'Calgary, AB' &&
        fb.ad.description.startsWith('For sale I have this small form factor Dell Optiplex 3040') &&
        fb.ad.extraValue('facebook.availability') == 'List as Single Item' &&
        fb.ad.extraValue('facebook.product_tags').contains('Windows 11'), fb.ad.title);
    check('facebook: price is the listing price, not the struck-through one', fb.ad.price != 100);
    check('facebook: listing URL comes from the page data',
        fb.ad.extraValue('facebook.listing_url') == 'https://www.facebook.com/marketplace/item/1891206475050655/', fb.ad.extraValue('facebook.listing_url'));
    check('facebook: category is reported missing (page has only an id)', fb.missing.join() == 'category', '${fb.missing}');
    check('facebook: seller name is not imported', !buildExportText(Marketplaces.facebook, fb.ad).contains('Brown'));
    final fbWithUrl = parseListing(Marketplaces.facebook, read('FacebookSource.txt'),
        url: Uri.parse('https://www.facebook.com/marketplace/item/1891206475050655/?referral_code=x'));
    check('facebook: link import keeps the id-matched listing and strips the query',
        fbWithUrl.ad.title.startsWith('i5 Dell') && fbWithUrl.ad.extraValue('facebook.listing_url') == 'https://www.facebook.com/marketplace/item/1891206475050655/');
    check('facebook import fails validation only on the missing category',
        validateAd(fb.ad).keys.join() == 'category', '${validateAd(fb.ad)}');
    for (final f in ['Karrot', 'Varagesale', 'Kijiji', 'Poshmark', 'eBay', 'Depop', 'Facebook']) {
      check('$f source auto-detects its provider', detectProviderFromSource(read('${f}Source.txt')) != null);
    }
    check('all real imports pass validation (kijiji description is 742 chars)',
        validateAd(kar.ad).isEmpty && validateAd(pm.ad).isEmpty && validateAd(vs.ad).isEmpty &&
            validateAd(kj.ad).isEmpty && kj.ad.description.length > 500,
        '${validateAd(kj.ad)}');
  }

  stdout.writeln(_failed == 0 ? '\nAll checks passed.' : '\n$_failed check(s) FAILED.');
  exit(_failed == 0 ? 0 : 1);
}
