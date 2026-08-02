import 'package:flutter/services.dart';

import '../models/prayer.dart';
import 'document_repository.dart';

/// The repository used wherever one is not injected. Shared because the cache
/// is per-instance: the prayers list and the notification-tap route each
/// building their own would parse the same eight assets twice.
final sharedPrayerRepository = PrayerRepository();

/// Reads the prayer texts bundled with the app.
///
/// Bundled rather than fetched, unlike the calendar: authored content that
/// never changes between releases, and it has to work with no signal at all.
///
/// A naming layer over [DocumentRepository], which does the reading, the
/// caching and the English fallback.
class PrayerRepository {
  PrayerRepository({AssetBundle? bundle, DocumentRepository? documents})
    : _documents = documents ?? DocumentRepository(bundle: bundle);

  final DocumentRepository _documents;

  /// The rule for [occasion] in [language], or null if it is not bundled.
  /// Falls back to English, so a language can be added file by file as it is
  /// translated.
  Future<PrayerSet?> load(PrayerOccasion occasion, String language) =>
      _documents.load(
        occasion.assetPath(language),
        fallbackPath: occasion.assetPath('en'),
      );

  void clearCache() => _documents.clearCache();
}
