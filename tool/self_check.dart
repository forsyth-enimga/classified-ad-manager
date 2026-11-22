// Plain-Dart checks of the core logic (no packages needed):
//   dart run tool/self_check.dart [optional-zip-output-path]
import 'dart:io';

import '../lib/core/ad.dart';
import '../lib/core/ad_filter.dart';
import '../lib/core/exporter.dart';
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

void main(List<String> args) {
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
  final long = depopDescription(ad);
  check('depop max-size ad stays within 1000', long.length <= kDepopTextMax, '${long.length}');

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
  check('description 501 chars fails',
      validateAd(sample()..description = 'a' * 501).containsKey('description'));
  check('description 500 chars passes',
      !validateAd(sample()..description = 'a' * 500).containsKey('description'));
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
  if (args.isNotEmpty) {
    File(args.first).writeAsBytesSync(zip);
    stdout.writeln('wrote ${args.first} (${zip.length} bytes)');
  }

  stdout.writeln(_failed == 0 ? '\nAll checks passed.' : '\n$_failed check(s) FAILED.');
  exit(_failed == 0 ? 0 : 1);
}
