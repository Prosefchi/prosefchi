import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/text_size.dart';
import 'package:prosefchi/screens/onboarding_screen.dart';
import 'package:prosefchi/screens/prayers_screen.dart';
import 'package:prosefchi/screens/settings_screen.dart';
import 'package:prosefchi/screens/today_screen.dart';
import 'package:prosefchi/services/prayer_repository.dart';
import 'package:prosefchi/services/settings_controller.dart';

import '../support/calendar_fixture.dart';
import '../support/fake_bundle.dart';
import '../support/memory_settings_store.dart';
import '../support/pump.dart';
import '../support/reminder_doubles.dart';

/// A size offered as an accessibility setting has to work on every screen, not
/// only the one it was added for.
///
/// Three of these overflowed before this existed: two rows on the day screen,
/// and the welcome screen's buttons — which broke at the *middle* size in
/// Greek, on the one screen the app opens on before anything else. None of it
/// is visible at the small size the other tests read at.
Widget scaled(
  TextSize size,
  Widget home, {
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  // Through TextSize.over, which is what the app scales by. Setting a bare
  // TextScaler.linear here would test a replica: `over` composes onto the
  // platform's size where linear replaces it, and that difference is the
  // whole substance of the setting.
  builder: (context, child) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: size.over(media.textScaler)),
      child: child!,
    );
  },
  home: home,
);

void main() {
  group('every screen fits at every size', () {
    for (final size in TextSize.values) {
      testWidgets('the day screen, at ${size.slug}', (tester) async {
        surface(tester, narrowSurface);

        await tester.pumpWidget(
          scaled(
            size,
            TodayScreen(
              repository: calendarsServing(
                calendarJson(
                  fasting: 'Wine and oil are allowed',
                  tone: 3,
                  eothinon: 5,
                ),
              ),
              prayers: PrayerRepository(bundle: FakeBundle(const {})),
              date: calendarFixtureDate,
            ),
          ),
        );
        await settle(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: 'the day screen overflows at ${size.slug}',
        );
      });

      // Greek runs longest, and the welcome screen broke here at medium.
      for (final locale in const [Locale('en'), Locale('el')]) {
        testWidgets('the welcome screen in ${locale.languageCode}, at '
            '${size.slug}', (tester) async {
          surface(tester, narrowSurface);

          final controller = SettingsController(store: MemorySettingsStore());
          await controller.load();
          await tester.pumpWidget(
            SettingsScope(
              controller: controller,
              child: scaled(
                size,
                OnboardingScreen(
                  reminderStore: MemoryReminderStore(),
                  scheduler: RecordingScheduler(),
                ),
                locale: locale,
              ),
            ),
          );
          await settle(tester);

          expect(
            tester.takeException(),
            isNull,
            reason:
                'the welcome screen overflows at ${size.slug} '
                'in ${locale.languageCode}',
          );
        });
      }

      testWidgets('the settings screen, at ${size.slug}', (tester) async {
        surface(tester, tallSurface);

        final controller = SettingsController(store: MemorySettingsStore());
        await controller.load();
        await tester.pumpWidget(
          SettingsScope(
            controller: controller,
            child: scaled(size, const SettingsScreen(about: SizedBox.shrink())),
          ),
        );
        await settle(tester);

        expect(
          tester.takeException(),
          isNull,
          reason: 'the settings screen overflows at ${size.slug}',
        );
      });
    }
  });

  testWidgets('a rule stays readable at the largest size', (tester) async {
    surface(tester, narrowSurface);

    const source = '''
# Evening Prayers

> A rubric telling the reader what to do at this point in the rule.

Glory to the Father and the Son and the Holy Spirit, now and forever and to
the ages of ages. Amen.
''';

    await tester.pumpWidget(
      scaled(TextSize.large, PrayerScreen(set: PrayerSet.parse(source))),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Evening Prayers'), findsOneWidget);
  });

  group('composes with the platform rather than replacing it', () {
    test('multiplies the size already asked for', () {
      // Someone who has set a system text size has said what they need. An app
      // that overwrites it takes it from exactly the reader this exists for.
      const platform = TextScaler.linear(1.5);

      expect(TextSize.small.over(platform).scale(10), 15);
      expect(TextSize.large.over(platform).scale(10), closeTo(27, 0.001));
      // Not 18, which is what replacing the platform scaler would give.
      expect(TextSize.large.over(platform).scale(10), isNot(18));
    });

    test('equal scalers compare equal, so text is not rebuilt for nothing', () {
      // MediaQuery decides whether to rebuild every text widget below it by
      // comparing scalers.
      const platform = TextScaler.linear(1.5);
      expect(TextSize.large.over(platform), TextSize.large.over(platform));
      expect(
        TextSize.large.over(platform),
        isNot(TextSize.medium.over(platform)),
      );
    });

    test('platformBase recovers what a size was composed onto', () {
      // The settings preview draws each option against the platform's size.
      // Composing onto the MediaQuery it sits in would multiply every option
      // by whatever is currently selected.
      const platform = TextScaler.linear(1.5);
      expect(TextSize.platformBase(TextSize.large.over(platform)), platform);
      // An unwrapped scaler is its own base.
      expect(TextSize.platformBase(platform), platform);
    });
  });
}
