import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosefchi/models/calendar.dart';
import 'package:prosefchi/models/reminder.dart';
import 'package:prosefchi/screens/settings_screen.dart';
import 'package:prosefchi/screens/today_screen.dart';
import 'package:prosefchi/services/calendar_repository.dart';
import 'package:prosefchi/services/prayer_repository.dart';
import 'package:prosefchi/services/settings_controller.dart';

import '../support/app.dart';
import '../support/calendar_fixture.dart';
import '../support/fake_bundle.dart';
import '../support/memory_calendar_store.dart';
import '../support/memory_settings_store.dart';
import '../support/pump.dart';
import '../support/reminder_doubles.dart';

Future<Widget> screenWith(
  Widget home, {
  CalendarStyle style = CalendarStyle.gregorian,
}) => settingsApp(
  SettingsController(
    store: MemorySettingsStore(language: 'en', calendarStyle: style.name),
  ),
  home: home,
);

void main() {
  group('TodayScreen', () {
    Widget today() => TodayScreen(
      repository: calendarsServing(calendarJson()),
      prayers: PrayerRepository(bundle: FakeBundle(const {})),
      date: calendarFixtureDate,
    );

    testWidgets('writes the Julian date under the civil one', (tester) async {
      await tester.pumpWidget(
        await screenWith(today(), style: CalendarStyle.julian),
      );
      await settle(tester);

      // 26 July 2026 is 13 July on the old calendar. The civil date keeps the
      // weekday and stays the headline, which is also why the weekday is
      // written once: julianDateOf returns calendar fields, not an instant.
      expect(find.textContaining('July 13, 2026'), findsOneWidget);
      expect(find.textContaining('Sunday, July 26, 2026'), findsOneWidget);
    });

    testWidgets('says nothing about it on the new calendar', (tester) async {
      await tester.pumpWidget(await screenWith(today()));
      await settle(tester);

      expect(find.textContaining('old calendar'), findsNothing);
      expect(find.textContaining('Sunday, July 26, 2026'), findsOneWidget);
    });
  });

  group('SettingsScreen', () {
    testWidgets('switching the calendar rebuilds the fasting block', (
      tester,
    ) async {
      // The block is a bounded horizon of one-off notifications whose days
      // were chosen under the old setting, and the daily refresh is throttled,
      // so without this someone who switched would keep being reminded to fast
      // on the other calendar's days until tomorrow.
      // The settings page is taller than the default surface, and a tap below
      // the fold misses silently.
      surface(tester, tallSurface);

      final scheduler = RecordingScheduler();
      final store = MemoryReminderStore()
        ..fasting = const FastingReminder(enabled: true, hour: 6, minute: 0);

      await tester.pumpWidget(
        await screenWith(
          SettingsScreen(
            reminderStore: store,
            scheduler: scheduler,
            calendars: offlineCalendars(),
            about: const SizedBox.shrink(),
          ),
        ),
      );
      await settle(tester);

      final before = scheduler.fastingApplies;
      await tester.tap(find.text('Old calendar (Julian)'));
      await settle(tester);

      expect(scheduler.fastingApplies, greaterThan(before));
    });
  });
}
