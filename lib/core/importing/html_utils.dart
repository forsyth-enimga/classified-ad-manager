import 'dart:convert';

/// Decodes the common HTML entities (named and numeric).
String decodeEntities(String s) {
  if (!s.contains('&')) return s;
  const named = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
    'rsquo': '’',
    'lsquo': '‘',
    'ldquo': '“',
    'rdquo': '”',
  };
  return s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
    final e = m.group(1)!;
    int? code;
    if (e.startsWith('#x')) {
      code = int.tryParse(e.substring(2), radix: 16);
    } else if (e.startsWith('#')) {
      code = int.tryParse(e.substring(1));
    } else {
      return named[e] ?? m.group(0)!;
    }
    if (code == null || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
      return m.group(0)!;
    }
    return String.fromCharCode(code);
  });
}

/// HTML -> readable text. Block tags and <br> become line breaks.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '')
      .replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '')
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li|ul|ol|h[1-6]|tr|table|section)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = decodeEntities(s).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ').trim());
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// HTML fragment -> one line of text.
String inlineText(String html) =>
    htmlToText(html).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Texts of all `<span>` elements in a fragment (empty ones skipped).
List<String> spanTexts(String html) => RegExp(r'<span\b[^>]*>(.*?)</span>', dotAll: true)
    .allMatches(html)
    .map((m) => inlineText(m.group(1)!))
    .where((t) => t.isNotEmpty)
    .toList();

/// Content of `<meta property|name="key" content="...">` (either attribute order).
String? metaContent(String html, String key) {
  final k = RegExp.escape(key);
  final a = RegExp('<meta[^>]+(?:property|name)=["\']$k["\'][^>]*?content=["\']([^"\']*)["\']',
      caseSensitive: false);
  final b = RegExp('<meta[^>]+content=["\']([^"\']*)["\'][^>]*?(?:property|name)=["\']$k["\']',
      caseSensitive: false);
  final m = a.firstMatch(html) ?? b.firstMatch(html);
  return m == null ? null : decodeEntities(m.group(1)!);
}

/// All JSON-LD objects on the page (arrays and @graph are flattened).
List<Map<String, dynamic>> jsonLdBlocks(String html) {
  final out = <Map<String, dynamic>>[];
  final re = RegExp(
    r'''<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script>''',
    caseSensitive: false,
    dotAll: true,
  );
  void collect(dynamic d) {
    if (d is List) {
      for (final e in d) {
        collect(e);
      }
    } else if (d is Map) {
      final m = Map<String, dynamic>.from(d);
      if (m['@graph'] is List) collect(m['@graph']);
      out.add(m);
    }
  }

  for (final m in re.allMatches(html)) {
    try {
      collect(jsonDecode(m.group(1)!.trim()));
    } catch (_) {
      // ignore malformed blocks
    }
  }
  return out;
}

bool ldIsType(Map<String, dynamic> m, String type) {
  final t = m['@type'];
  return t == type || (t is List && t.contains(type));
}

double? parseNumber(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final cleaned = v.toString().replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '');
  return double.tryParse(cleaned);
}

/// "35" -> "35.00" style for prices written into text fields.
String money(double v) => v.toStringAsFixed(2);
