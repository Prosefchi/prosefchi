import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/reminder.dart';
import 'package:prosefchi/screens/reminders_screen.dart';
import 'package:prosefchi/services/notification_service.dart';
import 'package:prosefchi/services/reminder_store.dart';

import '../support/app.dart';
import '../support/calendar_fixture.dart';
import '../support/pump.dart';
import '../support/reminder_doubles.dart';

Widget harness(
  ReminderStore store,
  ReminderScheduler scheduler, {
  Locale locale = const Locale('en'),
}) => localizedApp(
  locale: locale,
  home: RemindersScreen(
    store: store,
    scheduler: scheduler,
    calendars: offlineCalendars(),
  ),
);

void main() {
  testWidgets('lists every occasion with its own switch', (tester) async {
    await tester.pumpWidget(
      harness(MemoryReminderStore(), RecordingScheduler()),
    );
    await settle(tester);

    expect(
      find.byType(SwitchListTile),
      // The prayer rules, plus the fasting reminder below them.
      findsNWidgets(PrayerOccasion.values.length + 1),
    );
  });

  testWidgets('every reminder starts off', (tester) async {
    await tester.pumpWidget(
      harness(MemoryReminderStore(), RecordingScheduler()),
    );
    await settle(tester);

    final switches = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();

    expect(switches.where((s) => s.value), isEmpty);
  });

  testWidgets('switching one on persists and schedules only that one', (
    tester,
  ) async {
    // The whole point of a channel per occasion: they move independently.
    final store = MemoryReminderStore();
    final scheduler = RecordingScheduler();
    await tester.pumpWidget(harness(store, scheduler));
    await settle(tester);

    await tester.tap(find.text('Midday'));
    await settle(tester);

    expect(store.written, hasLength(1));
    expect(store.written.single.occasion, PrayerOccasion.midday);
    expect(store.written.single.enabled, isTrue);
    expect(scheduler.applied.single.occasion, PrayerOccasion.midday);
    expect(scheduler.titles.single, 'Midday');
  });

  testWidgets('switching one off still calls apply, which cancels it', (
    tester,
  ) async {
    // apply is responsible for cancelling a disabled reminder, so it must be
    // called rather than skipped.
    final scheduler = RecordingScheduler();
    final store = MemoryReminderStore({
      PrayerOccasion.morning: Reminder.defaultFor(
        PrayerOccasion.morning,
      ).copyWith(enabled: true),
    });
    await tester.pumpWidget(harness(store, scheduler));
    await settle(tester);

    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(scheduler.applied.single.occasion, PrayerOccasion.morning);
    expect(scheduler.applied.single.enabled, isFalse);
  });

  testWidgets('asks permission only when switching on', (tester) async {
    final scheduler = RecordingScheduler();
    final store = MemoryReminderStore({
      PrayerOccasion.morning: Reminder.defaultFor(
        PrayerOccasion.morning,
      ).copyWith(enabled: true),
    });
    await tester.pumpWidget(harness(store, scheduler));
    await settle(tester);

    await tester.tap(find.text('Morning')); // on -> off
    await settle(tester);
    expect(scheduler.permissionRequests, 0, reason: 'no prompt to turn off');

    await tester.tap(find.text('Midday')); // off -> on
    await settle(tester);
    expect(scheduler.permissionRequests, 1);
  });

  testWidgets('leaves the switch off when permission is declined', (
    tester,
  ) async {
    // Showing a reminder as enabled that can never fire is a lie.
    final store = MemoryReminderStore();
    final scheduler = RecordingScheduler(granted: false);
    await tester.pumpWidget(harness(store, scheduler));
    await settle(tester);

    await tester.tap(find.text('Midday'));
    await settle(tester);

    expect(store.written, isEmpty);
    expect(scheduler.applied, isEmpty);
    expect(
      find.text(
        'Notifications are turned off. Enable them in system settings to be reminded.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows Off rather than a time for a disabled reminder', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(MemoryReminderStore(), RecordingScheduler()),
    );
    await settle(tester);

    expect(find.text('Off'), findsNWidgets(PrayerOccasion.values.length));
  });

  testWidgets('groups the rules by kind', (tester) async {
    // Communion is not a daily rule: someone who receives monthly wants it on
    // a different footing from a morning one.
    await tester.pumpWidget(
      harness(MemoryReminderStore(), RecordingScheduler()),
    );
    await settle(tester);

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Liturgy'), findsOneWidget);
  });

  testWidgets('offers a fasting reminder alongside the prayer rules', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(MemoryReminderStore(), RecordingScheduler()),
    );
    await settle(tester);

    expect(find.text('Fasting'), findsOneWidget);
    expect(find.text('Only on the days that fast'), findsWidgets);
  });

  testWidgets('switching fasting on schedules the days that fast', (
    tester,
  ) async {
    surface(tester, tallSurface);
    // It is a block of one-off notifications rather than a repeating alarm,
    // because it must not fire on the days between.
    final store = MemoryReminderStore();
    final scheduler = RecordingScheduler();
    await tester.pumpWidget(harness(store, scheduler));
    await settle(tester);

    await tester.ensureVisible(find.text('Fasting'));
    await settle(tester);
    await tester.tap(find.text('Fasting'));
    await settle(tester);

    expect(store.fasting.enabled, isTrue);
    expect(scheduler.fastingDays, isNotEmpty);
    expect(scheduler.permissionRequests, 1);
  });

  testWidgets('switching fasting off clears the whole block', (tester) async {
    surface(tester, tallSurface);
    final store = MemoryReminderStore()
      ..fasting = const FastingReminder.initial().copyWith(enabled: true);
    final scheduler = RecordingScheduler();
    await tester.pumpWidget(harness(store, scheduler));
    await settle(tester);

    await tester.ensureVisible(find.text('Fasting'));
    await settle(tester);
    await tester.tap(find.text('Fasting'));
    await settle(tester);

    expect(store.fasting.enabled, isFalse);
    expect(scheduler.fastingDays, isEmpty);
  });

  testWidgets('defaults the fasting reminder to off, at six', (tester) async {
    // A fast is kept from waking, so a reminder after breakfast has missed it.
    const initial = FastingReminder.initial();

    expect(initial.enabled, isFalse);
    expect(initial.hour, 6);
    expect(initial.minute, 0);
  });

  testWidgets('labels the occasions in Greek under the el locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        MemoryReminderStore(),
        RecordingScheduler(),
        locale: const Locale('el'),
      ),
    );
    await settle(tester);

    expect(find.text('Υπενθυμίσεις'), findsOneWidget);
    expect(find.text('Καθημερινά'), findsOneWidget);
    expect(find.text('Θεία Λειτουργία'), findsOneWidget);
    expect(find.text('Πρωί'), findsOneWidget);
    expect(find.text('Ανενεργό'), findsWidgets);
  });
}
