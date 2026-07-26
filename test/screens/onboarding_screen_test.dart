import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/screens/onboarding_screen.dart';
import 'package:prosefchi/services/document_repository.dart';
import 'package:prosefchi/services/notification_service.dart';
import 'package:prosefchi/services/reminder_store.dart';
import 'package:prosefchi/services/settings_controller.dart';
import '../support/pump.dart';
import '../support/fake_bundle.dart';
import '../support/reminder_doubles.dart';

class _MemorySettingsStore implements SettingsStore {
  _MemorySettingsStore({this.language});

  String? language;
  bool onboardingSeen = false;

  @override
  Future<String?> readLanguage() async => language;

  @override
  Future<void> writeLanguage(String? value) async => language = value;

  @override
  Future<bool> readOnboardingSeen() async => onboardingSeen;

  @override
  Future<void> writeOnboardingSeen(bool seen) async => onboardingSeen = seen;
}

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
      ),
    ),
  );
}

void main() {
  testWidgets('opens on the welcome page rendered from markdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      await harness(SettingsController(store: _MemorySettingsStore())),
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
        SettingsController(store: _MemorySettingsStore(language: 'el')),
      ),
    );
    await settle(tester);

    expect(find.text('Καλώς ήρθατε'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing);
  });

  testWidgets('swipes to the reminders page', (tester) async {
    await tester.pumpWidget(
      await harness(SettingsController(store: _MemorySettingsStore())),
    );
    await settle(tester);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await settle(tester);

    expect(
      find.byType(SwitchListTile),
      // The prayer rules, plus the fasting reminder below them.
      findsNWidgets(PrayerOccasion.values.length + 1),
    );
  });

  testWidgets('offers every reminder switched off', (tester) async {
    await tester.pumpWidget(
      await harness(SettingsController(store: _MemorySettingsStore())),
    );
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);

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
        SettingsController(store: _MemorySettingsStore()),
        scheduler: scheduler,
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);

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
        SettingsController(store: _MemorySettingsStore()),
        scheduler: scheduler,
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(scheduler.applied, isEmpty);
  });

  testWidgets('finishing marks the welcome as seen', (tester) async {
    final store = _MemorySettingsStore();
    await tester.pumpWidget(await harness(SettingsController(store: store)));
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Get started'));
    await settle(tester);

    expect(store.onboardingSeen, isTrue);
  });

  testWidgets('skipping from the first page also marks it seen', (
    tester,
  ) async {
    // Otherwise it would reappear on every launch until endured in full.
    final store = _MemorySettingsStore();
    await tester.pumpWidget(await harness(SettingsController(store: store)));
    await settle(tester);

    await tester.tap(find.text('Skip'));
    await settle(tester);

    expect(store.onboardingSeen, isTrue);
  });
}
