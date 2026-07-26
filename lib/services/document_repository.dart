import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/markup.dart';

/// Reads authored documents bundled with the app.
///
/// Bundled rather than fetched: this is content that never changes between
/// releases and has to be there with no signal.
class DocumentRepository {
  DocumentRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  final Map<String, MarkupDocument?> _cache = {};

  /// The document at [assetPath], or [fallbackPath] if it is not bundled.
  ///
  /// The fallback lets a language be added a file at a time rather than all at
  /// once, with the untranslated pages still readable in English.
  Future<MarkupDocument?> load(String assetPath, {String? fallbackPath}) async {
    if (_cache.containsKey(assetPath)) return _cache[assetPath];

    final document =
        await _read(assetPath) ??
        (fallbackPath != null && fallbackPath != assetPath
            ? await _read(fallbackPath)
            : null);

    return _cache[assetPath] = document;
  }

  /// The welcome page for [language].
  Future<MarkupDocument?> welcome(String language) =>
      load('res/welcome_$language.md', fallbackPath: 'res/welcome_en.md');

  Future<MarkupDocument?> _read(String path) async {
    try {
      final document = MarkupDocument.parse(await _bundle.loadString(path));
      return document.isEmpty ? null : document;
    } on FlutterError {
      // Not bundled. Expected while a translation is outstanding.
      return null;
    } on Object catch (error) {
      debugPrint('documents: could not read $path ($error)');
      return null;
    }
  }

  void clearCache() => _cache.clear();
}
