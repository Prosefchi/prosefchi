import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/screens/prayers_screen.dart';
import 'package:prosefchi/screens/today_screen.dart';
import 'package:prosefchi/services/calendar_repository.dart';
import 'package:prosefchi/services/prayer_repository.dart';
import 'package:prosefchi/services/settings_controller.dart';

import '../support/fake_bundle.dart';
import '../support/memory_calendar_store.dart';
import '../support/pump.dart';

/// The day screen carries the most in the least room, so it is where a larger
/// text size shows up first.
///
/// A size offered as an accessibility setting has to work on the screen the
/// app opens on. Both of the rows this pins overflowed before it existed: the
/// liturgical strip at every width, and a section heading by 50 pixels even on
/// a wide phone. Neither is visible at the small size, which is why the sizes
/// are checked here rather than left to the tests that read text.
const _narrow = Size(1080, 2400); // 360 logical, about the narrowest shipped

String _dayJson() => jsonEncode({
  'language': 'en',
  'source': 'https://example.test/feed.ics',
  'generatedAt': '2026-07-26',
  'start': '2026-07-01',
  'end': '2026-08-31',
  'days': {
    '2026-07-26': {
      'title': 'Paraskeve the Righteous Martyr',
      'saints': ['Paraskeve the Righteous Martyr', 'Hermolaos the Holy Martyr'],
      'marks': ['majorFeast'],
      'fasting': 'Wine and oil are allowed',
      'tone': 3,
      'eothinon': 5,
      'gospel': {
        'reference': 'Mark 5:24-34',
        'text': 'At that time, a great crowd followed him.',
      },
    },
  },
});

void main() {
  for (final size in TextSize.values) {
    testWidgets('the day screen fits at ${size.slug}', (tester) async {
      tester.view.physicalSize = _narrow;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(size.scale)),
            child: child!,
          ),
          home: TodayScreen(
            repository: CalendarRepository(
              baseUrl: Uri.parse('https://example.test/'),
              client: MockClient(
                (_) async => http.Response.bytes(utf8.encode(_dayJson()), 200),
              ),
              store: MemoryCalendarStore(),
            ),
            prayers: PrayerRepository(bundle: FakeBundle(const {})),
            date: DateTime(2026, 7, 26, 7),
          ),
        ),
      );
      await settle(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the day screen overflows at the ${size.slug} text size',
      );
    });
  }

  testWidgets('a rule stays readable at the largest size', (tester) async {
    tester.view.physicalSize = _narrow;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const source = '''
# Evening Prayers

> A rubric telling the reader what to do at this point in the rule.

Glory to the Father and the Son and the Holy Spirit, now and forever and to
the ages of ages. Amen.
''';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(TextSize.large.scale)),
          child: child!,
        ),
        home: PrayerScreen(set: PrayerSet.parse(source)),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Evening Prayers'), findsOneWidget);
  });
}
