import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/reminder.dart';
import 'package:prosefchi/screens/settings_screen.dart';
import 'package:prosefchi/services/notification_service.dart';
import 'package:prosefchi/services/reminder_store.dart';
import 'package:prosefchi/services/settings_controller.dart';
import '../support/memory_calendar_store.dart';
import '../support/pump.dart';
import '../support/memory_settings_store.dart';
import '../support/reminder_doubles.dart';

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
          // Without this the language switch would reach the real file store
          // and http.Client, whose futures never complete under FakeAsync.
          calendars: offlineCalendars(),
          // The real one reaches for package_info_plus and url_launcher,
          // neither of which has a platform channel under flutter test.
          about: const SizedBox.shrink(key: Key('about')),
        ),
      ),
    ),
  );
}

/// The settings page is longer than the default 800x600 surface, and a
/// ListView does not build what it cannot show. Made taller rather than
/// scrolled, because a tap on a row below the fold misses silently and the
/// failure reads as a state assertion. The text size options make it longer
/// still: the largest is drawn at the size it selects.
void tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 5200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('offers system default alongside each language', (tester) async {
    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore(onboardingSeen: true)),
      ),
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
    final store = MemorySettingsStore(onboardingSeen: true);
    await tester.pumpWidget(
      await harness(
        SettingsController(store: store),
        reminderStore: MemoryReminderStore(),
        scheduler: RecordingScheduler(),
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
    final scheduler = RecordingScheduler();
    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore(onboardingSeen: true)),
        reminderStore: MemoryReminderStore({
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
    final scheduler = RecordingScheduler();
    final reminders = MemoryReminderStore({
      for (final occasion in PrayerOccasion.values)
        occasion: Reminder.defaultFor(occasion).copyWith(enabled: false),
    });
    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore(onboardingSeen: true)),
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
      await harness(
        SettingsController(
          store: MemorySettingsStore(language: 'el', onboardingSeen: true),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Ρυθμίσεις'), findsOneWidget);
  });

  testWidgets('ignores a stored language the app does not publish', (
    tester,
  ) async {
    // A downgrade, or a hand-edited preference. Falling back to the device is
    // better than crashing or showing an untranslated screen.
    final controller = SettingsController(
      store: MemorySettingsStore(language: 'fr', onboardingSeen: true),
    );
    await tester.pumpWidget(await harness(controller));
    await settle(tester);

    expect(controller.language, isNull);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('offers three text sizes, starting small', (tester) async {
    tallSurface(tester);
    final store = MemorySettingsStore(onboardingSeen: true);
    await tester.pumpWidget(await harness(SettingsController(store: store)));
    await settle(tester);

    expect(find.text('Text size'), findsOneWidget);
    for (final name in ['Small', 'Medium', 'Large']) {
      expect(find.text(name), findsOneWidget);
    }

    // Small is what the app drew before there was a choice, so an existing
    // reader's app must not change size under them on upgrade.
    final selected = tester
        .widgetList<RadioListTile<TextSize>>(
          find.byType(RadioListTile<TextSize>),
        )
        .map((tile) => tile.value);
    expect(selected, TextSize.values);
    expect(store.textSize, isNull, reason: 'nothing written until chosen');
  });

  testWidgets('choosing a size stores its slug, not its index', (tester) async {
    tallSurface(tester);
    final store = MemorySettingsStore(onboardingSeen: true);
    final controller = SettingsController(store: store);
    await tester.pumpWidget(await harness(controller));
    await settle(tester);

    await tester.tap(find.text('Large'));
    await settle(tester);

    expect(controller.textSize, TextSize.large);
    // A slug, so inserting or reordering a size cannot silently change what a
    // device already has.
    expect(store.textSize, 'large');
  });

  testWidgets('restores a stored size, and falls back when unknown', (
    tester,
  ) async {
    final medium = SettingsController(
      store: MemorySettingsStore(onboardingSeen: true, textSize: 'medium'),
    );
    await medium.load();
    expect(medium.textSize, TextSize.medium);

    // Written by a later build than this one, or hand-edited.
    final unknown = SettingsController(
      store: MemorySettingsStore(onboardingSeen: true, textSize: 'gigantic'),
    );
    await unknown.load();
    expect(unknown.textSize, TextSize.small);
  });

  testWidgets('replays the welcome from the last row', (tester) async {
    tallSurface(tester);

    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore(onboardingSeen: true)),
        reminderStore: MemoryReminderStore(),
        scheduler: RecordingScheduler(),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Show the welcome again'));
    await settle(tester);

    expect(find.byType(PageView), findsOneWidget);
  });

  testWidgets('carries an about section at the bottom', (tester) async {
    tallSurface(tester);

    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore(onboardingSeen: true)),
      ),
    );
    await settle(tester);

    expect(find.text('About'), findsOneWidget);
    expect(find.byKey(const Key('about')), findsOneWidget);
  });

  testWidgets('opens the reminders screen', (tester) async {
    tallSurface(tester);

    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore(onboardingSeen: true)),
        reminderStore: MemoryReminderStore(),
        scheduler: RecordingScheduler(),
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
