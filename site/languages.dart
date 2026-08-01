// How the site lays languages out in its URLs.
//
// The rule itself lives in lib/models/site.dart, where the app can reach it
// too: its about section links to the privacy policy published here, and that
// URL has to be the one the generator writes. Re-exported so the two symbols
// the site's compiled code needs arrive beside [withoutLanguage], which is a
// site concern and stays here. Only those two — anything reaching for the rest
// of site.dart imports it directly rather than through a file about languages.
//
// Flutter-free, like everything else the site compiles.

import 'package:prosefchi/models/calendar.dart' show supportedLanguages;
import 'package:prosefchi/models/site.dart' show prefixFor;

export 'package:prosefchi/models/calendar.dart' show supportedLanguages;
export 'package:prosefchi/models/site.dart' show prefixFor;

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
