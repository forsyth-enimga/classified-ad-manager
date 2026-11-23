import '../marketplaces.dart';

enum ImportErrorKind {
  invalidUrl,
  unsupportedProvider,
  network,
  blocked,
  loginRequired,
  notFound,
  noListingData,
}

/// A user-presentable import failure.
class ImportException implements Exception {
  ImportException(this.kind, this.message);

  final ImportErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Supported provider names for error messages.
String get supportedProvidersText =>
    Marketplaces.all.map((m) => m.name).join(', ');

/// Matches a link to a marketplace by its domain. Returns null if none match.
/// Short-link hosts (ebay.us, fb.me) are accepted here; the redirect target is
/// matched again after fetching.
Marketplace? providerForUrl(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;
  bool isDomain(String d) => host == d || host.endsWith('.$d');

  if (isDomain('kijiji.ca')) return Marketplaces.kijiji;
  if (isDomain('facebook.com') || isDomain('fb.com') || host == 'fb.me') {
    return Marketplaces.facebook;
  }
  if (RegExp(r'(^|\.)ebay\.[a-z]{2,3}(\.[a-z]{2})?$').hasMatch(host) ||
      host == 'ebay.us' ||
      host.endsWith('.ebay.us')) {
    return Marketplaces.ebay;
  }
  if (isDomain('varagesale.com')) return Marketplaces.varagesale;
  if (isDomain('karrotmarket.com') || isDomain('karrot.com')) {
    return Marketplaces.karrot;
  }
  if (isDomain('poshmark.ca') || isDomain('poshmark.com')) {
    return Marketplaces.poshmark;
  }
  if (isDomain('depop.com')) return Marketplaces.depop;
  return null;
}

/// Parses what the user typed. Adds https:// when the scheme is missing.
Uri parseUserUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) {
    throw ImportException(ImportErrorKind.invalidUrl, 'Paste a listing link first.');
  }
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(s)) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      !uri.host.contains('.')) {
    throw ImportException(
        ImportErrorKind.invalidUrl, 'That does not look like a valid web link.');
  }
  return uri;
}

/// A stable form of a listing URL for duplicate detection (no query, no
/// fragment, no trailing slash, lower-case host, no "www.").
String normalizeListingUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return url.trim();
  var host = u.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  var path = u.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '$host$path';
}
