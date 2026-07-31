// The site's strings, read from the app's own ARB files at runtime.
//
// `lib/l10n/app_en.arb` and `app_el.arb` are already JSON, and
// tool/build_site.dart copies them to the site root untouched. So the site
// does not hold a second copy of any string the app has: a translation fixed
// in the app is fixed here on the next deploy, with nothing to keep in step.
//
// The generated `AppLocalizations` cannot be reused instead — it is Flutter
// code, and pulling Flutter in is exactly what this site avoids. What is
// needed of it is small: key lookup, one placeholder, and two plurals.

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A looked-up string table for one language.
class Strings {
  const Strings(this._values);

  final Map<String, String> _values;

  /// Builds a table from the served string table.
  ///
  /// tool/build_site.dart writes that file by merging site/extra_strings.json
  /// over the app's ARB, so this only has to read flat string entries. The
  /// `@key` guard is belt and braces in case the ARB is ever served raw.
  factory Strings.fromJson(Map<String, dynamic> json) => Strings({
    for (final entry in json.entries)
      if (!entry.key.startsWith('@') &&
          !entry.key.startsWith('_') &&
          entry.value is String)
        entry.key: entry.value as String,
  });

  /// The string for [key].
  ///
  /// Falls back to the key itself. A missing string should look wrong on the
  /// page rather than throw and take the whole render down with it — the rest
  /// of the day is still worth showing.
  String operator [](String key) => _values[key] ?? key;

  /// A string carrying a count, whether or not it varies with one.
  ///
  /// A plain `{placeholder}` is substituted; an ICU plural — `{count, plural,
  /// =0{…} =1{…} other{…}}` — selects a case first. One method because the
  /// caller should not have to know which shape a translator used, and because
  /// substituting is what a plural does once its case is chosen anyway.
  ///
  /// Only the exact-match and `other` selectors are handled, which is all the
  /// two plural strings in the ARB use. `few`/`many` and the rest would need
  /// CLDR plural rules per language, and a case this cannot resolve falls
  /// through to `other` — wrong wording rather than a broken page.
  String plural(String key, int value) {
    final source = this[key];
    final opener = _pluralOpener.firstMatch(source);
    if (opener == null) return _substitute(source, value);

    final options = _selectors(source, opener.end);
    final body = options['=$value'] ?? options['other'];
    return body == null ? '$value' : _substitute(body, value);
  }
}

final _pluralOpener = RegExp(r'^\s*\{\s*\w+\s*,\s*plural\s*,');

final _placeholder = RegExp(r'\{\w+\}');

String _substitute(String source, int value) =>
    source.replaceAll(_placeholder, '$value');

/// The `selector{body}` pairs of a plural message, from [start].
Map<String, String> _selectors(String source, int start) {
  final selectors = <String, String>{};
  var index = start;

  while (index < source.length) {
    final open = source.indexOf('{', index);
    if (open < 0) break;

    final selector = source.substring(index, open).trim();
    // The message's own closing brace, once the last option is consumed.
    if (selector.isEmpty && selectors.isNotEmpty) break;

    final close = _closingBrace(source, open);
    if (close < 0) break;

    selectors[selector] = source.substring(open + 1, close);
    index = close + 1;
  }
  return selectors;
}

/// The index of the `}` matching the `{` at [open], or -1 if unbalanced.
///
/// Counting rather than searching, because an option body holds braces of its
/// own: `other{{count} days until Pascha}`.
int _closingBrace(String source, int open) {
  var depth = 0;
  for (var index = open; index < source.length; index++) {
    switch (source[index]) {
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) return index;
    }
  }
  return -1;
}

/// Fetches and parses the string table served at [url].
Future<Strings> loadStrings(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return const Strings({});
    final body = await response.text().toDart;
    return Strings.fromJson(jsonDecode(body.toDart) as Map<String, dynamic>);
  } on Object {
    // Every key then renders as itself, which is ugly but legible, and the
    // day's commemoration and readings still appear.
    return const Strings({});
  }
}
