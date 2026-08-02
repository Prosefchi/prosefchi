import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/calendar.dart';
import 'package:prosefchi/screens/today_screen.dart';
import 'package:prosefchi/services/prayer_repository.dart';
import 'package:prosefchi/services/settings_controller.dart';

import '../support/app.dart';
import '../support/calendar_fixture.dart';
import '../support/fake_bundle.dart';
import '../support/memory_settings_store.dart';
import '../support/pump.dart';

/// The day screen under a chosen calendar.
///
/// Its own wrapper rather than `today_screen_test.dart`'s, which builds on
/// `localizedApp` and so has no settings above it to read the style from.
Future<Widget> dayScreenWith(CalendarStyle style, {String language = 'en'}) =>
    settingsApp(
      SettingsController(
        store: MemorySettingsStore(
          language: language,
          calendarStyle: style.name,
        ),
      ),
      home: TodayScreen(
        repository: calendarsServing(calendarJson(language: language)),
        prayers: PrayerRepository(bundle: FakeBundle(const {})),
        date: calendarFixtureDate,
      ),
    );

void main() {
  testWidgets('writes the Julian date under the civil one', (tester) async {
    await tester.pumpWidget(await dayScreenWith(CalendarStyle.julian));
    await settle(tester);

    // 26 July 2026 is 13 July on the old calendar. The civil date keeps the
    // weekday and stays the headline, which is also why the weekday is written
    // once: julianDateOf returns calendar fields, not an instant.
    expect(find.textContaining('July 13, 2026'), findsOneWidget);
    expect(find.textContaining('Sunday, July 26, 2026'), findsOneWidget);
  });

  testWidgets('says nothing about it on the new calendar', (tester) async {
    await tester.pumpWidget(await dayScreenWith(CalendarStyle.gregorian));
    await settle(tester);

    expect(find.textContaining('old calendar'), findsNothing);
    expect(find.textContaining('Sunday, July 26, 2026'), findsOneWidget);
  });

  testWidgets('offers no retry where nothing is published', (tester) async {
    // Only English has a Julian calendar. A Greek reader who chooses the old
    // one still gets the computed fast and tone, so this is a designed state —
    // and a Retry button that can never succeed reads as the app being broken.
    await tester.pumpWidget(
      await dayScreenWith(CalendarStyle.julian, language: 'el'),
    );
    await settle(tester);

    expect(find.text('Δοκιμή ξανά'), findsNothing);
    expect(
      find.textContaining('δεν δημοσιεύονται'),
      findsOneWidget,
      reason: 'says what is missing rather than that a download failed',
    );
  });
}
