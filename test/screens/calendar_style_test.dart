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
  group('CalendarRepository', () {
    test('asks for the file the chosen calendar is published as', () async {
      final asked = <String>[];
      final repository = CalendarRepository(
        baseUrl: Uri.parse('https://example.test/'),
        client: MockClient((request) async {
          asked.add(request.url.path);
          return http.Response(calendarJson(), 200);
        }),
        store: MemoryCalendarStore(),
      );

      await repository.refresh('en');
      await repository.refresh('en', style: CalendarStyle.julian);

      expect(asked, ['/calendar.en.json', '/calendar.en.julian.json']);
    });

    test('keeps the two apart in the store and the cache', () async {
      // Same language, two files. Sharing a key would serve whichever was
      // fetched last under both settings.
      final repository = CalendarRepository(
        baseUrl: Uri.parse('https://example.test/'),
        client: MockClient(
          (request) async => request.url.path.contains('julian')
              ? http.Response(calendarJson(title: 'Old calendar day'), 200)
              : http.Response(calendarJson(title: 'New calendar day'), 200),
        ),
        store: MemoryCalendarStore(),
      );

      await repository.refresh('en');
      await repository.refresh('en', style: CalendarStyle.julian);

      expect(
        (await repository.load('en'))?.forDate(calendarFixtureDate)?.title,
        'New calendar day',
      );
      expect(
        (await repository.load(
          'en',
          style: CalendarStyle.julian,
        ))?.forDate(calendarFixtureDate)?.title,
        'Old calendar day',
      );
    });

    test('a combination nothing publishes reads as no calendar', () async {
      // Only English has a Julian file. A Greek reader who chooses the old
      // calendar falls back to the computed layer rather than seeing an error.
      final repository = CalendarRepository(
        baseUrl: Uri.parse('https://example.test/'),
        client: MockClient((_) async => http.Response('nope', 404)),
        store: MemoryCalendarStore(),
      );

      expect(
        await repository.refresh('el', style: CalendarStyle.julian),
        isFalse,
      );
      expect(await repository.load('el', style: CalendarStyle.julian), isNull);
    });
  });

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
