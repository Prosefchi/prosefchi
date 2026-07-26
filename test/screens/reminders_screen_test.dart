import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/reminder.dart';
import 'package:prosefchi/screens/reminders_screen.dart';
import 'package:prosefchi/services/notification_service.dart';
import 'package:prosefchi/services/reminder_store.dart';

class _MemoryReminderStore implements ReminderStore {
  _MemoryReminderStore([Map<PrayerOccasion, Reminder>? initial])
    : _reminders = {
        for (final occasion in PrayerOccasion.values)
          occasion: initial?[occasion] ?? Reminder.defaultFor(occasion),
      };

  final Map<PrayerOccasion, Reminder> _reminders;
  final List<Reminder> written = [];

  @override
  Future<Map<PrayerOccasion, Reminder>> readAll() async => {..._reminders};

  @override
  Future<void> write(Reminder reminder) async {
    _reminders[reminder.occasion] = reminder;
    written.add(reminder);
  }
}

class _RecordingScheduler implements ReminderScheduler {
  _RecordingScheduler({this.granted = true});

  final bool granted;
  final List<Reminder> applied = [];
  final List<String> titles = [];
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> apply(
    Reminder reminder, {
    required String channelName,
    required String title,
    required String body,
  }) async {
    applied.add(reminder);
    titles.add(title);
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget harness(
  ReminderStore store,
  ReminderScheduler scheduler, {
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: RemindersScreen(store: store, scheduler: scheduler),
);

void main() {
  testWidgets('lists every occasion with its own switch', (tester) async {
    await tester.pumpWidget(
      harness(_MemoryReminderStore(), _RecordingScheduler()),
    );
    await settle(tester);

    expect(
      find.byType(SwitchListTile),
      findsNWidgets(PrayerOccasion.values.length),
    );
  });

  testWidgets('every reminder starts off', (tester) async {
    await tester.pumpWidget(
      harness(_MemoryReminderStore(), _RecordingScheduler()),
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
    final store = _MemoryReminderStore();
    final scheduler = _RecordingScheduler();
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
    final scheduler = _RecordingScheduler();
    final store = _MemoryReminderStore({
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
    final scheduler = _RecordingScheduler();
    final store = _MemoryReminderStore({
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
    final store = _MemoryReminderStore();
    final scheduler = _RecordingScheduler(granted: false);
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
      harness(_MemoryReminderStore(), _RecordingScheduler()),
    );
    await settle(tester);

    expect(find.text('Off'), findsNWidgets(PrayerOccasion.values.length));
  });

  testWidgets('labels the occasions in Greek under the el locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        _MemoryReminderStore(),
        _RecordingScheduler(),
        locale: const Locale('el'),
      ),
    );
    await settle(tester);

    expect(find.text('Υπενθυμίσεις'), findsOneWidget);
    expect(find.text('Πρωί'), findsOneWidget);
    expect(find.text('Ανενεργό'), findsWidgets);
  });
}
