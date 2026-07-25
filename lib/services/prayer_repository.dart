import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/prayer.dart';

/// Reads the prayer texts bundled with the app.
///
/// Bundled rather than fetched, unlike the calendar: prayers are authored
/// content that never changes between releases, and they have to work with no
/// signal at all. Someone praying on the metro, on a plane, or in a monastery
/// is exactly the case the app exists for.
class PrayerRepository {
  PrayerRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  final Map<String, PrayerSet?> _cache = {};

  /// The rule for [occasion] in [language], or null if it is not bundled.
  ///
  /// Falls back to English rather than failing, so adding a language means
  /// adding files as they are translated rather than all at once.
  Future<PrayerSet?> load(PrayerOccasion occasion, String language) async {
    final key = '${occasion.slug}_$language';
    if (_cache.containsKey(key)) return _cache[key];

    final set =
        await _read(occasion.assetPath(language)) ??
        (language == 'en' ? null : await _read(occasion.assetPath('en')));

    return _cache[key] = set;
  }

  Future<PrayerSet?> _read(String path) async {
    try {
      final source = await _bundle.loadString(path);
      final set = PrayerSet.parse(source);
      return set.isEmpty ? null : set;
    } on FlutterError {
      // Not bundled. Expected while a translation is still outstanding.
      return null;
    } on Object catch (error) {
      debugPrint('prayers: could not read $path ($error)');
      return null;
    }
  }

  void clearCache() => _cache.clear();
}
