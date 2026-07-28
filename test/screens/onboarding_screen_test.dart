import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/text_size.dart';
import 'package:prosefchi/screens/onboarding_screen.dart';
import 'package:prosefchi/services/document_repository.dart';
import 'package:prosefchi/services/notification_service.dart';
import 'package:prosefchi/services/reminder_store.dart';
import 'package:prosefchi/services/settings_controller.dart';
import '../support/pump.dart';
import '../support/app.dart';
import '../support/fake_bundle.dart';
import '../support/memory_settings_store.dart';
import '../support/reminder_doubles.dart';

const welcomeEn = '''
# Welcome

Prosefchi keeps the day's commemoration to hand.
''';

const welcomeEl = '''
# Καλώς ήρθατε

Η Προσευχή έχει πρόχειρη την εορτή της ημέρας.
''';

Future<Widget> harness(
  SettingsController controller, {
  ReminderStore? reminderStore,
  ReminderScheduler? scheduler,
}) => settingsApp(
  controller,
  home: OnboardingScreen(
    documents: DocumentRepository(
      bundle: FakeBundle({
        'res/welcome_en.md': welcomeEn,
        'res/welcome_el.md': welcomeEl,
      }),
    ),
    reminderStore: reminderStore ?? MemoryReminderStore(),
    scheduler: scheduler ?? RecordingScheduler(),
  ),
);

/// Advances to the reminders page, which is the last of the three.
///
/// The reader page sits between the greeting and the reminders, so reaching
/// the reminders takes two taps rather than one.
Future<void> toReminders(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.text('Next'));
    await settle(tester);
  }
}

void main() {
  testWidgets('opens on the welcome page rendered from markdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      await harness(SettingsController(store: MemorySettingsStore())),
    );
    await settle(tester);

    expect(find.text('Welcome'), findsOneWidget);
    expect(
      find.text("Prosefchi keeps the day's commemoration to hand."),
      findsOneWidget,
    );
  });

  testWidgets('renders the welcome in the chosen language', (tester) async {
    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore(language: 'el')),
      ),
    );
    await settle(tester);

    expect(find.text('Καλώς ήρθατε'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing);
  });

  testWidgets('swipes to the reminders page', (tester) async {
    await tester.pumpWidget(
      await harness(SettingsController(store: MemorySettingsStore())),
    );
    await settle(tester);

    for (var i = 0; i < 2; i++) {
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await settle(tester);
    }

    expect(
      find.byType(SwitchListTile),
      // The prayer rules, plus the fasting reminder below them.
      findsNWidgets(PrayerOccasion.values.length + 1),
    );
  });

  group('the reader page', () {
    // Two radio groups with the largest option drawn at its own size make this
    // page taller than the default surface, and a tap below the fold misses
    // silently, so every test here sets one before building the tree.
    Future<void> toReader(WidgetTester tester) async {
      await tester.tap(find.text('Next'));
      await settle(tester);
    }

    testWidgets('offers both settings between welcome and reminders', (
      tester,
    ) async {
      surface(tester, tallSurface);
      await tester.pumpWidget(
        await harness(SettingsController(store: MemorySettingsStore())),
      );
      await settle(tester);
      await toReader(tester);

      expect(find.text('Set up your reading'), findsOneWidget);
      expect(find.text('System default'), findsOneWidget);
      expect(find.text('Ελληνικά'), findsOneWidget);
      for (final size in ['Small', 'Medium', 'Large']) {
        expect(find.text(size), findsOneWidget);
      }
      // Still ahead of the reminders, not replacing them.
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('choosing a size here is what the reader gets', (tester) async {
      surface(tester, tallSurface);
      final store = MemorySettingsStore();
      final controller = SettingsController(store: store);
      await tester.pumpWidget(await harness(controller));
      await settle(tester);
      await toReader(tester);

      await tester.tap(find.text('Large'));
      await settle(tester);

      expect(controller.textSize, TextSize.large);
      expect(store.textSize, 'large');
    });

    testWidgets('choosing a language switches the flow immediately', (
      tester,
    ) async {
      surface(tester, tallSurface);
      final store = MemorySettingsStore();
      await tester.pumpWidget(await harness(SettingsController(store: store)));
      await settle(tester);
      await toReader(tester);

      await tester.tap(find.text('Ελληνικά'));
      await settle(tester);

      expect(store.language, 'el');
      // The page the choice was made on is now in Greek.
      expect(find.text('Set up your reading'), findsNothing);
    });
  });

  testWidgets('offers every reminder switched off', (tester) async {
    await tester.pumpWidget(
      await harness(SettingsController(store: MemorySettingsStore())),
    );
    await settle(tester);
    await toReminders(tester);

    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switches.where((s) => s.value), isEmpty);
  });

  testWidgets('prompts for permission when the first reminder is enabled', (
    tester,
  ) async {
    // The whole reason reminders ship off: the prompt arrives when the user
    // asks for a notification, not before.
    final scheduler = RecordingScheduler();
    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore()),
        scheduler: scheduler,
      ),
    );
    await settle(tester);
    await toReminders(tester);

    expect(scheduler.permissionRequests, 0, reason: 'not asked on arrival');

    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(scheduler.permissionRequests, 1);
    expect(scheduler.applied.single.occasion, PrayerOccasion.morning);
    expect(scheduler.applied.single.enabled, isTrue);
  });

  testWidgets('does not enable a reminder when permission is declined', (
    tester,
  ) async {
    final scheduler = RecordingScheduler(granted: false);
    await tester.pumpWidget(
      await harness(
        SettingsController(store: MemorySettingsStore()),
        scheduler: scheduler,
      ),
    );
    await settle(tester);
    await toReminders(tester);
    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(scheduler.applied, isEmpty);
  });

  testWidgets('finishing marks the welcome as seen', (tester) async {
    final store = MemorySettingsStore();
    await tester.pumpWidget(await harness(SettingsController(store: store)));
    await settle(tester);
    await toReminders(tester);
    await tester.tap(find.text('Get started'));
    await settle(tester);

    expect(store.onboardingSeen, isTrue);
  });

  testWidgets('skipping from the first page also marks it seen', (
    tester,
  ) async {
    // Otherwise it would reappear on every launch until endured in full.
    final store = MemorySettingsStore();
    await tester.pumpWidget(await harness(SettingsController(store: store)));
    await settle(tester);

    await tester.tap(find.text('Skip'));
    await settle(tester);

    expect(store.onboardingSeen, isTrue);
  });
}
