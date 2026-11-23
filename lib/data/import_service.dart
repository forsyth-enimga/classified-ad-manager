import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/importing/listing_parser.dart';
import '../core/importing/providers.dart';
import '../core/marketplaces.dart';

class _Page {
  _Page(this.finalUrl, this.status, this.body);
  final Uri finalUrl;
  final int status;
  final String body;
}

/// Downloads a listing page and turns it into an unsaved [Ad].
/// All failures are reported as [ImportException] with a readable message.
class ImportService {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const String _blockedHint =
      'Open the listing in your browser, view its page source, copy it, and use "Import from pasted page source".';

  /// Import from a link the user typed or pasted.
  Future<ParsedListing> importFromUrl(String raw) async {
    final uri = parseUserUrl(raw);
    if (providerForUrl(uri) == null) {
      throw ImportException(
        ImportErrorKind.unsupportedProvider,
        'That link is not from a supported site. Supported sites: $supportedProvidersText.',
      );
    }

    final page = await _fetch(uri);

    // Short links (ebay.us, fb.me) redirect; match the final address again.
    final provider = providerForUrl(page.finalUrl);
    if (_isLoginUrl(page.finalUrl)) {
      throw ImportException(
        ImportErrorKind.loginRequired,
        'The site sent us to a login page, so the listing could not be read.',
      );
    }
    if (provider == null) {
      throw ImportException(
        ImportErrorKind.unsupportedProvider,
        'That link redirected to ${page.finalUrl.host}, which is not a supported site.',
      );
    }
    _checkStatus(provider, page.status);

    final descHtml = provider.id == 'ebay' ? await _ebayDescription(page.body) : null;
    return parseListing(
      provider,
      page.body,
      url: page.finalUrl,
      ebayDescriptionHtml: descHtml,
    );
  }

  /// Import from page source the user pasted. [provider] null = auto-detect.
  Future<ParsedListing> importFromSource(String html, {Marketplace? provider}) async {
    if (html.trim().length < 200) {
      throw ImportException(
        ImportErrorKind.noListingData,
        'That is too short to be a page. Paste the whole page source (Ctrl+U in your browser, then select all and copy).',
      );
    }
    final p = provider ?? detectProviderFromSource(html);
    if (p == null) {
      throw ImportException(
        ImportErrorKind.unsupportedProvider,
        'Could not tell which site this page is from. Choose the site from the list and try again.',
      );
    }
    final descHtml = p.id == 'ebay' ? await _ebayDescription(html) : null;
    return parseListing(p, html, ebayDescriptionHtml: descHtml);
  }

  /// eBay keeps the seller's description on a separate page. Failure to get it
  /// is not fatal: the description is left blank for the user to fill in.
  Future<String?> _ebayDescription(String html) async {
    final url = ebayDescriptionUrl(html);
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    try {
      final page = await _fetch(uri);
      return page.status < 400 ? page.body : null;
    } catch (_) {
      return null;
    }
  }

  bool _isLoginUrl(Uri u) =>
      RegExp(r'/(log-?in|sign-?in|sign_in|checkpoint|ie/login|signin)(/|$|\?)', caseSensitive: false)
          .hasMatch(u.path);

  void _checkStatus(Marketplace provider, int status) {
    if (status == 401) {
      throw ImportException(
        ImportErrorKind.loginRequired,
        '${provider.name} requires you to log in to see this listing.',
      );
    }
    if (status == 403 || status == 429 || status == 503) {
      throw ImportException(
        ImportErrorKind.blocked,
        '${provider.name} blocked the request (HTTP $status). $_blockedHint',
      );
    }
    if (status == 404 || status == 410) {
      throw ImportException(
        ImportErrorKind.notFound,
        'The listing was not found. It may have been sold, expired or removed.',
      );
    }
    if (status >= 400) {
      throw ImportException(
        ImportErrorKind.network,
        '${provider.name} returned an error (HTTP $status). Try again later.',
      );
    }
  }

  Future<_Page> _fetch(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = _userAgent;
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      req.headers
        ..set(HttpHeaders.acceptHeader,
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8')
        ..set(HttpHeaders.acceptLanguageHeader, 'en-CA,en;q=0.9');
      req.followRedirects = true;
      req.maxRedirects = 8;
      final res = await req.close().timeout(const Duration(seconds: 25));

      var finalUrl = uri;
      for (final r in res.redirects) {
        finalUrl = finalUrl.resolveUri(r.location);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        bytes.add(chunk);
        if (bytes.length > 8 * 1024 * 1024) break;
      }
      // Decode as UTF-8 without failing on stray bytes.
      final body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
      return _Page(finalUrl, res.statusCode, body);
    } on TimeoutException {
      throw ImportException(
        ImportErrorKind.network,
        'The site took too long to respond. Check your connection and try again.',
      );
    } on SocketException {
      throw ImportException(
        ImportErrorKind.network,
        'Could not reach the site. Check your internet connection.',
      );
    } on HandshakeException {
      throw ImportException(
        ImportErrorKind.network,
        'A secure connection to the site could not be made.',
      );
    } on HttpException catch (e) {
      throw ImportException(ImportErrorKind.network, 'Network error: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }
}
