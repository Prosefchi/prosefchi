import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/reminder.dart';
import 'package:prosefchi/screens/settings_screen.dart';
import 'package:prosefchi/services/notification_service.dart';
import 'package:prosefchi/services/reminder_store.dart';
import 'package:prosefchi/services/settings_controller.dart';

class _MemorySettingsStore implements SettingsStore {
  _MemorySettingsStore([this.language]);

  String? language;
  bool onboardingSeen = true;
  int writes = 0;

  @override
  Future<String?> readLanguage() async => language;

  @override
  Future<void> writeLanguage(String? value) async {
    language = value;
    writes++;
  }

  @override
  Future<bool> readOnboardingSeen() async => onboardingSeen;

  @override
  Future<void> writeOnboardingSeen(bool seen) async => onboardingSeen = seen;
}

class _MemoryReminderStore implements ReminderStore {
  _MemoryReminderStore([Map<PrayerOccasion, Reminder>? initial])
    : _reminders = {
        for (final occasion in PrayerOccasion.values)
          occasion: initial?[occasion] ?? Reminder.defaultFor(occasion),
      };

  final Map<PrayerOccasion, Reminder> _reminders;

  @override
  Future<Map<PrayerOccasion, Reminder>> readAll() async => {..._reminders};

  @override
  Future<void> write(Reminder reminder) async =>
      _reminders[reminder.occasion] = reminder;

  FastingReminder fasting = const FastingReminder.initial();

  @override
  Future<FastingReminder> readFasting() async => fasting;

  @override
  Future<void> writeFasting(FastingReminder reminder) async =>
      fasting = reminder;
}

class _RecordingScheduler implements ReminderScheduler {
  List<({DateTime date, String body})> fastingDays = const [];
  final List<String> titles = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> apply(
    Reminder reminder, {
    required String channelName,
    required String title,
    required String body,
  }) async => titles.add(title);

  @override
  Future<void> applyFasting(
    FastingReminder reminder, {
    required List<({DateTime date, String body})> days,
    required String channelName,
    required String title,
  }) async {
    fastingDays = reminder.enabled ? days : const [];
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<Widget> harness(
  SettingsController controller, {
  ReminderStore? reminderStore,
  ReminderScheduler? scheduler,
}) async {
  await controller.load();
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SettingsScope(
      controller: controller,
      child: MaterialApp(
        locale: controller.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(
          reminderStore: reminderStore,
          scheduler: scheduler,
          // The real one reaches for package_info_plus and url_launcher,
          // neither of which has a platform channel under flutter test.
          about: const SizedBox.shrink(key: Key('about')),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('offers system default alongside each language', (tester) async {
    await tester.pumpWidget(
      await harness(SettingsController(store: _MemorySettingsStore())),
    );
    await settle(tester);

    expect(find.text('System default'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    // Greek is named in Greek whatever the current language, so a Greek
    // speaker can find it from an English UI.
    expect(find.text('Ελληνικά'), findsOneWidget);
  });

  testWidgets('choosing Greek switches the interface immediately', (
    tester,
  ) async {
    final store = _MemorySettingsStore();
    await tester.pumpWidget(
      await harness(
        SettingsController(store: store),
        reminderStore: _MemoryReminderStore(),
        scheduler: _RecordingScheduler(),
      ),
    );
    await settle(tester);

    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Ελληνικά'));
    await settle(tester);

    expect(find.text('Ρυθμίσεις'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(store.language, 'el');
  });

  testWidgets('reschedules enabled reminders in the new language', (
    tester,
  ) async {
    // Notification text is baked in at schedule time, so without this every
    // pending reminder would stay in the old language until it was toggled.
    final scheduler = _RecordingScheduler();
    await tester.pumpWidget(
      await harness(
        SettingsController(store: _MemorySettingsStore()),
        reminderStore: _MemoryReminderStore({
          for (final occasion in [PrayerOccasion.morning, PrayerOccasion.night])
            occasion: Reminder.defaultFor(occasion).copyWith(enabled: true),
        }),
        scheduler: scheduler,
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Ελληνικά'));
    await settle(tester);

    expect(scheduler.titles, ['Πρωί', 'Βράδυ']);
  });

  testWidgets('leaves disabled reminders alone', (tester) async {
    final scheduler = _RecordingScheduler();
    final reminders = _MemoryReminderStore({
      for (final occasion in PrayerOccasion.values)
        occasion: Reminder.defaultFor(occasion).copyWith(enabled: false),
    });
    await tester.pumpWidget(
      await harness(
        SettingsController(store: _MemorySettingsStore()),
        reminderStore: reminders,
        scheduler: scheduler,
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Ελληνικά'));
    await settle(tester);

    expect(scheduler.titles, isEmpty);
  });

  testWidgets('restores a previously chosen language on load', (tester) async {
    await tester.pumpWidget(
      await harness(SettingsController(store: _MemorySettingsStore('el'))),
    );
    await settle(tester);

    expect(find.text('Ρυθμίσεις'), findsOneWidget);
  });

  testWidgets('ignores a stored language the app does not publish', (
    tester,
  ) async {
    // A downgrade, or a hand-edited preference. Falling back to the device is
    // better than crashing or showing an untranslated screen.
    final controller = SettingsController(store: _MemorySettingsStore('fr'));
    await tester.pumpWidget(await harness(controller));
    await settle(tester);

    expect(controller.language, isNull);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('replays the welcome from the last row', (tester) async {
    await tester.pumpWidget(
      await harness(
        SettingsController(store: _MemorySettingsStore()),
        reminderStore: _MemoryReminderStore(),
        scheduler: _RecordingScheduler(),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Show the welcome again'));
    await settle(tester);

    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('carries an about section at the bottom', (tester) async {
    // It is the last thing on the page, past the default 800x600 surface, and
    // a ListView does not build what it cannot show.
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      await harness(SettingsController(store: _MemorySettingsStore())),
    );
    await settle(tester);

    expect(find.text('About'), findsOneWidget);
    expect(find.byKey(const Key('about')), findsOneWidget);
  });

  testWidgets('opens the reminders screen', (tester) async {
    await tester.pumpWidget(
      await harness(
        SettingsController(store: _MemorySettingsStore()),
        reminderStore: _MemoryReminderStore(),
        scheduler: _RecordingScheduler(),
      ),
    );
    await settle(tester);

    await tester.tap(
      find.text('Choose which prayers to be reminded of, and when'),
    );
    await settle(tester);

    expect(
      find.byType(SwitchListTile),
      // The prayer rules, plus the fasting reminder below them.
      findsNWidgets(PrayerOccasion.values.length + 1),
    );
  });
}
