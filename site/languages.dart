// How the site lays languages out in its URLs.
//
// Shared by the generator and the browser: tool/build_site.dart writes the
// pages at these paths and site/day.dart resolves `?lang=` against the same
// rule. Two statements of it would mean the generator writing one set of URLs
// and the client-side redirect sending readers to another — a 404 on the one
// path nobody tests by hand.
//
// Flutter-free, like everything else the site compiles.

import 'package:prosefchi/models/calendar.dart' show supportedLanguages;

export 'package:prosefchi/models/calendar.dart' show supportedLanguages;

/// The path prefix a language's pages sit under, relative to the site root.
///
/// English is served at the root and every other language under its own code,
/// so the canonical URL of the front page carries nothing extra.
String prefixFor(String language) =>
    language == supportedLanguages.first ? '' : '$language/';

/// [path] with any language prefix removed, leaving the part shared by every
/// translation of a page.
String withoutLanguage(String path) {
  for (final language in supportedLanguages) {
    final prefix = prefixFor(language);
    if (prefix.isNotEmpty && path.startsWith(prefix)) {
      return path.substring(prefix.length);
    }
  }
  return path;
}
