import 'dart:convert';
import 'dart:typed_data';

import 'ad.dart';
import 'marketplaces.dart';
import 'zip_writer.dart';

String _normalizeNewlines(String s) => s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _sharedValue(Ad ad, SharedKey key) {
  switch (key) {
    case SharedKey.title:
      return ad.title.trim();
    case SharedKey.description:
      return _normalizeNewlines(ad.description).trim();
    case SharedKey.price:
      return ad.price == null ? '' : ad.price!.toStringAsFixed(2);
    case SharedKey.category:
      return ad.category.trim();
    case SharedKey.condition:
      return ad.condition.trim();
    case SharedKey.location:
      return ad.location.trim();
  }
}

String _ownValue(Ad ad, FieldDef f) {
  switch (f.type) {
    case FieldType.checkbox:
      return ad.extraBool(f.key) ? 'Yes' : 'No';
    case FieldType.list:
      return splitList(ad.extraValue(f.key)).join(', ');
    case FieldType.text:
    case FieldType.multiline:
    case FieldType.number:
    case FieldType.dropdown:
      return _normalizeNewlines(ad.extraValue(f.key)).trim();
  }
}

/// The value written for one export entry.
String entryValue(Marketplace m, Entry e, Ad ad) {
  if (e.computed != null) return e.computed!(ad);
  if (e.shared != null) {
    if (e.overridable) {
      final o = ad.extraValue(m.overrideKey(e.shared!)).trim();
      if (o.isNotEmpty) return _normalizeNewlines(o);
    }
    return _sharedValue(ad, e.shared!);
  }
  return _ownValue(ad, e.field!);
}

/// Builds the export file for one marketplace.
///
/// Format, for every field of that marketplace only:
///
///     Field name
///     value
///
/// A multi-line value keeps its line breaks. Empty optional fields are written
/// with a blank value line so the layout stays predictable when pasting.
String buildExportText(Marketplace m, Ad ad) {
  final b = StringBuffer();
  for (final e in m.entries) {
    b.write(e.label);
    b.write('\n');
    b.write(entryValue(m, e, ad));
    b.write('\n');
  }
  return b.toString();
}

/// Problems worth confirming before saving the file (none block the export).
List<String> exportWarnings(Marketplace m, Ad ad) {
  final w = <String>[];
  for (final f in m.ownFields) {
    final v = ad.extraValue(f.key).trim();
    if (v.isEmpty) continue;
    if (f.maxLength != null && v.length > f.maxLength!) {
      w.add('${f.label} is ${v.length} characters; ${m.name} allows ${f.maxLength}.');
    }
    if (f.type == FieldType.list &&
        f.maxItems != null &&
        splitList(v).length > f.maxItems!) {
      w.add('${f.label} has ${splitList(v).length} items; ${m.name} allows ${f.maxItems}.');
    }
  }
  if (m.id == 'poshmark' && ad.description.trim().length > kPoshmarkDescriptionWarn) {
    w.add('Description is ${ad.description.trim().length} characters; Poshmark has been '
        'reported to allow only $kPoshmarkDescriptionWarn, so it may be cut off.');
  }
  if (m.id == 'depop') {
    final text = depopDescription(ad);
    if (text.length > kDepopTextMax) {
      w.add('Depop description (title + description + hashtags) is '
          '${text.length} characters; Depop allows $kDepopTextMax.');
    }
    final tags = RegExp(r'#\w+').allMatches(text).length;
    if (tags > kDepopMaxHashtags) {
      w.add('Depop text contains $tags hashtags; Depop allows $kDepopMaxHashtags.');
    }
    if (RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+').hasMatch(text)) {
      w.add('Depop does not allow email addresses in the description.');
    }
  }
  return w;
}

String slugify(String s, {int maxLength = 40}) {
  var slug = s
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > maxLength) {
    slug = slug.substring(0, maxLength).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.isEmpty ? 'ad' : slug;
}

/// e.g. `Samsung-23_kijiji.txt`
String exportFileName(Ad ad, Marketplace m) => '${slugify(ad.title)}_${m.id}.txt';

/// All marketplaces for one ad, bundled as a zip (one .txt per marketplace).
Uint8List buildAllZip(Ad ad) {
  final entries = <ZipEntry>[
    for (final m in Marketplaces.all)
      ZipEntry(exportFileName(ad, m), Uint8List.fromList(utf8.encode(buildExportText(m, ad)))),
  ];
  return buildZip(entries);
}

String exportZipName(Ad ad) => '${slugify(ad.title)}_all-platforms.zip';
