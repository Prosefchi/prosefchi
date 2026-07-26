import 'package:flutter/services.dart';

import '../models/prayer.dart';
import 'document_repository.dart';

/// Reads the prayer texts bundled with the app.
///
/// Bundled rather than fetched, unlike the calendar: prayers are authored
/// content that never changes between releases, and they have to work with no
/// signal at all. Someone praying on the metro, on a plane, or in a monastery
/// is exactly the case the app exists for.
///
/// A thin naming layer over [DocumentRepository], which already does the
/// reading, the caching and the English fallback. All this adds is the mapping
/// from an occasion to its two candidate paths.
class PrayerRepository {
  PrayerRepository({AssetBundle? bundle, DocumentRepository? documents})
    : _documents = documents ?? DocumentRepository(bundle: bundle);

  final DocumentRepository _documents;

  /// The rule for [occasion] in [language], or null if it is not bundled.
  ///
  /// Falls back to English rather than failing, so adding a language means
  /// adding files as they are translated rather than all at once. When
  /// [language] is already English the fallback is the same path and is not
  /// read twice.
  Future<PrayerSet?> load(PrayerOccasion occasion, String language) =>
      _documents.load(
        occasion.assetPath(language),
        fallbackPath: occasion.assetPath('en'),
      );

  void clearCache() => _documents.clearCache();
}
