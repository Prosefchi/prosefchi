import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/reminder.dart';
import 'package:prosefchi/screens/home_shell.dart';
import 'package:prosefchi/screens/prayers_screen.dart';
import 'package:prosefchi/services/document_repository.dart';
import 'package:prosefchi/services/prayer_repository.dart';

import '../support/fake_bundle.dart';
import '../support/pump.dart';
import '../support/reminder_doubles.dart';

/// Enough of a rule to render, for every occasion in both languages.
FakeBundle bundleWithEveryRule() => FakeBundle({
  for (final occasion in PrayerOccasion.values)
    for (final language in ['en', 'el'])
      occasion.assetPath(language): '# ${occasion.slug}\n\nΚύριε ἐλέησον.\n',
});

Widget harness({
  required RecordingScheduler scheduler,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: HomeShell(
    scheduler: scheduler,
    prayers: PrayerRepository(
      documents: DocumentRepository(bundle: bundleWithEveryRule()),
    ),
  ),
);

void main() {
  testWidgets('opens the rule a tapped prayer reminder is for', (tester) async {
    final scheduler = RecordingScheduler();

    await tester.pumpWidget(harness(scheduler: scheduler));
    await settle(tester);
    expect(find.byType(PrayerScreen), findsNothing);

    scheduler.tap(const PrayerTarget(PrayerOccasion.beforeCommunion));
    await settle(tester);

    // The rule itself, not merely the list it is on.
    expect(find.byType(PrayerScreen), findsOne);
    expect(find.text('before_communion'), findsOne);
  });

  testWidgets('opens a rule when the tap launched the app', (tester) async {
    // The path the plugin cannot report through the stream: the process did not
    // exist when the notification was tapped, so nothing was listening.
    final scheduler = RecordingScheduler()
      ..launchTarget = const PrayerTarget(PrayerOccasion.night);

    await tester.pumpWidget(harness(scheduler: scheduler));
    await settle(tester);

    expect(find.text('night'), findsOne);
  });

  testWidgets('a tapped fasting reminder shows the day', (tester) async {
    final scheduler = RecordingScheduler();

    await tester.pumpWidget(harness(scheduler: scheduler));
    await settle(tester);

    // Move away first, so landing on the day is the tap's doing and not just
    // the tab the app opens on.
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await settle(tester);

    scheduler.tap(const FastingTarget());
    await settle(tester);

    // The day, and no rule pushed over it.
    expect(find.byIcon(Icons.today), findsOne);
    expect(find.byType(PrayerScreen), findsNothing);
  });

  testWidgets('opens nothing when the app was launched normally', (
    tester,
  ) async {
    await tester.pumpWidget(harness(scheduler: RecordingScheduler()));
    await settle(tester);

    expect(find.byType(PrayerScreen), findsNothing);
  });
}
