// How the site lays languages out in its URLs: the rule from
// lib/models/site.dart, re-exported beside the one part of it that is the
// site's own.

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
