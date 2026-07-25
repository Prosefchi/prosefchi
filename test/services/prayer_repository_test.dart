import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/services/prayer_repository.dart';

/// Serves only the assets it is given, throwing for anything else the way the
/// real bundle does for an asset that was never bundled.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.contents);

  final Map<String, String> contents;
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    final value = contents[key];
    if (value == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(utf8.encode(value));
  }
}

void main() {
  test('reads the bundled rule for the requested language', () async {
    final repository = PrayerRepository(
      bundle: _FakeBundle({
        'res/prayers/morning_el.md': '# Πρωινὲς Προσευχές\n\nἈμήν.\n',
      }),
    );

    final set = await repository.load(PrayerOccasion.morning, 'el');

    expect(set?.title, 'Πρωινὲς Προσευχές');
  });

  test('falls back to English when a translation is missing', () async {
    // Adding a language should mean adding files as they are translated, not
    // all of them before any of them work.
    final bundle = _FakeBundle({
      'res/prayers/night_en.md': '# Evening Prayers\n\nAmen.\n',
    });
    final repository = PrayerRepository(bundle: bundle);

    final set = await repository.load(PrayerOccasion.night, 'el');

    expect(set?.title, 'Evening Prayers');
    expect(bundle.requested, [
      'res/prayers/night_el.md',
      'res/prayers/night_en.md',
    ]);
  });

  test('returns null when neither the language nor English is bundled', () async {
    final repository = PrayerRepository(bundle: _FakeBundle({}));

    expect(await repository.load(PrayerOccasion.midday, 'el'), isNull);
  });

  test('does not fall back from English to itself', () async {
    final bundle = _FakeBundle({});
    final repository = PrayerRepository(bundle: bundle);

    expect(await repository.load(PrayerOccasion.morning, 'en'), isNull);
    expect(bundle.requested, ['res/prayers/morning_en.md'], reason: 'one read');
  });

  test('caches hits and misses alike', () async {
    final bundle = _FakeBundle({
      'res/prayers/morning_en.md': '# Morning Prayers\n\nAmen.\n',
    });
    final repository = PrayerRepository(bundle: bundle);

    await repository.load(PrayerOccasion.morning, 'en');
    await repository.load(PrayerOccasion.morning, 'en');
    await repository.load(PrayerOccasion.midday, 'en');
    await repository.load(PrayerOccasion.midday, 'en');

    expect(bundle.requested, hasLength(2));
  });

  test('treats a file with no content as absent', () async {
    final repository = PrayerRepository(
      bundle: _FakeBundle({'res/prayers/midday_en.md': '<!-- todo -->\n'}),
    );

    expect(await repository.load(PrayerOccasion.midday, 'en'), isNull);
  });
}
