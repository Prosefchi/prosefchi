// The site's strings, read from the app's own ARB files at runtime, so the site
// holds no second copy of any string the app has.
//
// The generated `AppLocalizations` cannot be reused: it is Flutter code, and
// what is needed of it is small — key lookup, one placeholder, two plurals.

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A looked-up string table for one language.
class Strings {
  const Strings(this._values);

  final Map<String, String> _values;

  /// The served file is already flattened; the `@key` guard is in case the ARB
  /// is ever served raw.
  factory Strings.fromJson(Map<String, dynamic> json) => Strings({
    for (final entry in json.entries)
      if (!entry.key.startsWith('@') &&
          !entry.key.startsWith('_') &&
          entry.value is String)
        entry.key: entry.value as String,
  });

  /// Falls back to the key itself: a missing string should look wrong on the
  /// page rather than take the whole render down.
  String operator [](String key) => _values[key] ?? key;

  /// A string carrying a count, whether or not it varies with one. A plain
  /// `{placeholder}` is substituted; an ICU plural selects a case first.
  ///
  /// Only exact-match and `other` selectors are handled, which is all the ARB
  /// uses; `few`/`many` would need CLDR rules per language, and an unresolved
  /// case falls through to `other`.
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
    // Every key then renders as itself: ugly, but the day still appears.
    return const Strings({});
  }
}
