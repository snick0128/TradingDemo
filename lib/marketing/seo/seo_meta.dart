import 'dart:html' as html;
import 'dart:convert';

/// Updates document-level SEO tags (title, description, canonical, Open
/// Graph, Twitter card) for the current marketing route.
///
/// Flutter web is client-side rendered, so these tags are written after the
/// app boots — search engines that execute JS (Googlebot) and social-card
/// scrapers that request the page after hydration will see them; the static
/// defaults in web/index.html cover the very first paint / non-JS fetchers.
class SeoMeta {
  static const String _baseUrl = 'https://tradekosh.com';
  static const String _jsonLdId = 'tk-route-jsonld';

  static void set({
    required String title,
    required String description,
    required String path,
    String? imagePath,
  }) {
    final canonicalUrl = '$_baseUrl$path';
    final image = imagePath ?? '$_baseUrl/icons/Icon-512.png';

    html.document.title = title;

    _setMetaByName('description', description);
    _setMetaByProperty('og:title', title);
    _setMetaByProperty('og:description', description);
    _setMetaByProperty('og:url', canonicalUrl);
    _setMetaByProperty('og:image', image);
    _setMetaByName('twitter:title', title);
    _setMetaByName('twitter:description', description);

    _setCanonical(canonicalUrl);
  }

  /// Injects (or replaces) a single JSON-LD structured-data block for the
  /// current route. Call with `null` data to remove it when leaving a page.
  static void setJsonLd(Map<String, dynamic>? data) {
    final existing = html.document.getElementById(_jsonLdId);
    existing?.remove();
    if (data == null) return;

    final script = html.ScriptElement()
      ..id = _jsonLdId
      ..type = 'application/ld+json'
      ..text = jsonEncode(data);
    html.document.head!.append(script);
  }

  static void _setMetaByName(String name, String content) {
    var tag = html.document.querySelector('meta[name="$name"]');
    if (tag == null) {
      tag = html.MetaElement()..setAttribute('name', name);
      html.document.head!.append(tag);
    }
    tag.setAttribute('content', content);
  }

  static void _setMetaByProperty(String property, String content) {
    var tag = html.document.querySelector('meta[property="$property"]');
    if (tag == null) {
      tag = html.MetaElement()..setAttribute('property', property);
      html.document.head!.append(tag);
    }
    tag.setAttribute('content', content);
  }

  static void _setCanonical(String url) {
    var link = html.document.querySelector('link[rel="canonical"]');
    if (link == null) {
      link = html.LinkElement()..rel = 'canonical';
      html.document.head!.append(link);
    }
    link.setAttribute('href', url);
  }
}
