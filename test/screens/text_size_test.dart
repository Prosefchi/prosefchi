import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/text_size.dart';
import 'package:prosefchi/models/calendar.dart';
import 'package:prosefchi/screens/onboarding_screen.dart';
import 'package:prosefchi/screens/prayers_screen.dart';
import 'package:prosefchi/screens/settings_screen.dart';
import 'package:prosefchi/screens/today_screen.dart';
import 'package:prosefchi/services/prayer_repository.dart';
import 'package:prosefchi/services/settings_controller.dart';

import '../support/app.dart';
import '../support/calendar_fixture.dart';
import '../support/fake_bundle.dart';
import '../support/memory_settings_store.dart';
import '../support/pump.dart';
import '../support/reminder_doubles.dart';

/// Every screen has to survive a large text size, whoever asked for it.
///
/// The in-app setting reaches only the prayer passage, but the platform's own
/// text size reaches everything and always has, and Android allows up to 2.0.
/// These pump each screen at the same multipliers the setting offers, standing
/// in for a system size of the same magnitude.
///
/// Three screens overflowed before this existed: two rows on the day screen,
/// and the welcome screen's buttons, which broke at the *middle* step in Greek
/// — the one screen the app opens on before anything else. None of it is
/// visible at the default the other tests read at.
Widget scaled(
  TextSize size,
  Widget home, {
  Locale locale = const Locale('en'),
}) => localizedApp(
  locale: locale,
  // Through TextSize.over, which is what the prayer screen scales by. A bare
  // TextScaler.linear would test a replica: `over` composes onto the platform's
  // size where linear replaces it, and that difference is the substance of it.
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
                  // The longest rule in both languages, which is what makes
                  // this an overflow test at the large sizes.
                  fastAllowance: FastAllowance.dairyEggsAndFish,
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

  testWidgets('the chosen size reaches the passage and not the app bar', (
    tester,
  ) async {
    // The setting exists for reading a rule. The app bar is chrome, and every
    // other screen is scanned rather than read, so neither grows with it.
    final controller = SettingsController(
      store: MemorySettingsStore(textSize: 'large'),
    );
    await controller.load();

    await tester.pumpWidget(
      SettingsScope(
        controller: controller,
        child: localizedApp(
          home: PrayerScreen(
            set: PrayerSet.parse('# Evening Prayers\n\nLord, have mercy.\n'),
          ),
        ),
      ),
    );
    await settle(tester);

    double scalerAt(String text) =>
        tester.widget<Text>(find.text(text)).textScaler?.scale(10) ??
        MediaQuery.textScalerOf(tester.element(find.text(text))).scale(10);

    expect(
      scalerAt('Lord, have mercy.'),
      closeTo(10 * TextSize.large.scale, 0.001),
      reason: 'the passage grows',
    );
    expect(
      scalerAt('Evening Prayers'),
      10,
      reason: 'the app bar title does not',
    );
  });

  testWidgets('falls back to the default with no settings above it', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedApp(
        home: PrayerScreen(set: PrayerSet.parse('# A\n\nLord, have mercy.\n')),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Lord, have mercy.'), findsOneWidget);
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
  });
}
