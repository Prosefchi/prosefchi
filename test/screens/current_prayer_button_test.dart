import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/screens/current_prayer_button.dart';
import 'package:prosefchi/screens/prayers_screen.dart';
import 'package:prosefchi/services/prayer_repository.dart';

import '../support/app.dart';
import '../support/fake_bundle.dart';
import '../support/pump.dart';

const morning = '''
# Morning Prayers

In the name of the Father, and of the Son, and of the Holy Spirit. Amen.
''';

const midday = '''
# Midday Prayers

Glory to You, our God, glory to You.
''';

const placeholder = '''
# Evening Prayers

> [Awaiting text: the evening rule, said before sleep.]
''';

const everyRule = {
  'res/prayers/morning_en.md': morning,
  'res/prayers/midday_en.md': midday,
  'res/prayers/night_en.md': placeholder,
};

/// The button on a page of its own, with the hour it is to believe.
Widget harness(
  DateTime Function() clock, {
  Map<String, String> assets = everyRule,
  Locale locale = const Locale('en'),
}) => localizedApp(
  locale: locale,
  home: Scaffold(
    body: CurrentPrayerButton(
      clock: clock,
      repository: PrayerRepository(bundle: FakeBundle(assets)),
    ),
  ),
);

DateTime Function() fixedAt(int hour) =>
    () => DateTime(2026, 7, 26, hour);

/// Puts the app away and brings it back, which is when the hour is read again.
///
/// Every state in between, in order: `AppLifecycleListener` asserts on a
/// transition the platform could not have made.
Future<void> resume(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await settle(tester);
}

void main() {
  testWidgets('offers the rule the hour belongs to', (tester) async {
    await tester.pumpWidget(harness(fixedAt(8)));
    await settle(tester);

    expect(find.text('Pray now'), findsOne);
    expect(find.text('Morning'), findsOne);
  });

  testWidgets('follows the clock into the next window', (tester) async {
    await tester.pumpWidget(harness(fixedAt(13)));
    await settle(tester);

    expect(find.text('Midday'), findsOne);
    expect(find.text('Morning'), findsNothing);
  });

  testWidgets('opens the rule it names', (tester) async {
    await tester.pumpWidget(harness(fixedAt(8)));
    await settle(tester);

    await tester.tap(find.text('Morning'));
    await settle(tester);

    // The rule itself, not merely the list it is on.
    expect(find.byType(PrayerScreen), findsOne);
    expect(find.text('Morning Prayers'), findsOne);
  });

  testWidgets('offers nothing outside the hours a rule belongs to', (
    tester,
  ) async {
    // Four in the afternoon belongs to no rule, and reaching for whichever is
    // nearest would offer the morning prayers to someone at their desk.
    await tester.pumpWidget(harness(fixedAt(16)));
    await settle(tester);

    expect(find.text('Pray now'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('offers nothing for a rule whose text is still awaited', (
    tester,
  ) async {
    // The evening rule is a marked gap. A hero button onto an empty page is a
    // worse promise than no button.
    await tester.pumpWidget(harness(fixedAt(19)));
    await settle(tester);

    expect(find.text('Pray now'), findsNothing);
    expect(find.text('Evening'), findsNothing);
  });

  testWidgets('offers nothing for a rule that is not bundled', (tester) async {
    await tester.pumpWidget(harness(fixedAt(8), assets: const {}));
    await settle(tester);

    expect(find.text('Pray now'), findsNothing);
  });

  testWidgets('reads the hour again when the app is resumed', (tester) async {
    // The day screen is kept alive for the life of the process, so its build
    // runs about once per launch: a phone opened at breakfast and opened again
    // after lunch would otherwise still be offering the morning rule.
    var hour = 8;
    await tester.pumpWidget(harness(() => DateTime(2026, 7, 26, hour)));
    await settle(tester);
    expect(find.text('Morning'), findsOne);

    hour = 13;
    await resume(tester);

    expect(find.text('Midday'), findsOne);
    expect(find.text('Morning'), findsNothing);
  });

  testWidgets('takes itself off the page when the window closes', (
    tester,
  ) async {
    var hour = 13;
    await tester.pumpWidget(harness(() => DateTime(2026, 7, 26, hour)));
    await settle(tester);
    expect(find.text('Midday'), findsOne);

    hour = 16;
    await resume(tester);

    expect(find.text('Pray now'), findsNothing);
  });

  testWidgets('names the rule in Greek under the el locale', (tester) async {
    await tester.pumpWidget(
      harness(
        fixedAt(8),
        assets: const {
          'res/prayers/morning_el.md': '# Πρωινὲς Προσευχές\n\nἈμήν.\n',
        },
        locale: const Locale('el'),
      ),
    );
    await settle(tester);

    expect(find.text('Προσευχηθείτε τώρα'), findsOne);
    expect(find.text('Πρωί'), findsOne);
  });
}
