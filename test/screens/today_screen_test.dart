import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/screens/today_screen.dart';
import 'package:prosefchi/services/calendar_repository.dart';
import 'package:prosefchi/services/prayer_repository.dart';

import '../support/fake_bundle.dart';
import '../support/calendar_fixture.dart';
import '../support/pump.dart';

void main() {
  Widget harness(
    CalendarRepository repository, {
    Locale locale = const Locale('en'),
    DateTime? date,
    Map<String, String> prayers = const {},
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TodayScreen(
      repository: repository,
      prayers: PrayerRepository(bundle: FakeBundle(prayers)),
      // Midnight unless a test says otherwise, which belongs to no prayer
      // window, so the current-prayer button stays out of the way of the tests
      // that are not about it.
      date: date ?? calendarFixtureDate,
    ),
  );

  testWidgets('shows the commemoration, marks and reading', (tester) async {
    await tester.pumpWidget(harness(calendarsServing(calendarJson())));
    await settle(tester);

    // Once as the headline, once in the commemorations list.
    expect(find.text('Paraskeve the Righteous Martyr'), findsNWidgets(2));
    // The bullet is drawn rather than prefixed to the string, so the name is
    // the whole of the text a screen reader announces.
    expect(find.text('Hermolaos the Holy Martyr'), findsOneWidget);
    expect(find.text('Mark 5:24-34'), findsOneWidget);
    expect(find.text('Gospel'), findsOneWidget);

    // Marks render as labelled chips rather than raw emoji in the headline.
    expect(find.text('Great feast'), findsOneWidget);
  });

  testWidgets('renders Greek labels under the el locale', (tester) async {
    await tester.pumpWidget(
      harness(
        calendarsServing(
          calendarJson(
            language: 'el',
            title: 'Παρασκευή η Οσιομάρτυς',
            saints: const ['Παρασκευή η Οσιομάρτυς', 'Ερμόλαος ο Ιερομάρτυς'],
            marks: const ['majorFeast'],
            fasting: 'Ημέρα Νηστείας (Κατάλυσις ιχθύος)',
            gospelReference: 'Κατὰ Μᾶρκον 5:24-34',
          ),
        ),
        locale: const Locale('el'),
      ),
    );
    await settle(tester);

    expect(find.text('Σήμερα'), findsOneWidget);
    expect(find.text('Ευαγγέλιο'), findsOneWidget);
    expect(find.text('Ημέρα Νηστείας (Κατάλυσις ιχθύος)'), findsOneWidget);
    expect(find.text('Παρασκευή η Οσιομάρτυς'), findsWidgets);
  });

  testWidgets('falls back to computed data when nothing is cached', (
    tester,
  ) async {
    // A first launch with no network: the app must still say something rather
    // than show an error, because the Paschalion needs no data at all.
    await tester.pumpWidget(harness(calendarsServing(null)));
    await settle(tester);

    // Pascha 2026 is 12 April; 26 July is 105 days after it.
    expect(find.text('105 days after Pascha'), findsOneWidget);
    expect(
      find.text('The calendar has not been downloaded yet'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('distinguishes an uncovered date from a missing calendar', (
    tester,
  ) async {
    // The published feed stops at 2026-08-31, so dates past it are a normal
    // state with a different message from "nothing downloaded".
    await tester.pumpWidget(
      harness(calendarsServing(calendarJson()), date: DateTime(2026, 9, 15)),
    );
    await settle(tester);

    expect(find.text('No entry for this day'), findsOneWidget);
    expect(find.text('The calendar has not been downloaded yet'), findsNothing);
  });

  testWidgets('does not repeat the headline as a one-item list', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        calendarsServing(
          calendarJson(saints: const ['Paraskeve the Righteous Martyr']),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Saints and Feasts'), findsNothing);
    expect(
      find.text('Paraskeve the Righteous Martyr'),
      findsOneWidget,
      reason: 'the headline only, with no list repeating it',
    );
  });

  testWidgets('folds the reading text away behind its citation', (
    tester,
  ) async {
    // Two passages of several hundred words each is what turned this page
    // into a slab. The citation is what people scan for.
    await tester.pumpWidget(harness(calendarsServing(calendarJson())));
    await settle(tester);

    const passage =
        'At that time, a great crowd followed him and thronged about him.';
    expect(find.text('Mark 5:24-34'), findsOneWidget);
    expect(find.text(passage), findsNothing);

    await tester.tap(find.text('Gospel'));
    await settle(tester);

    expect(find.text(passage), findsOneWidget);
  });

  testWidgets('shows the fasting rule and drops the redundant mark', (
    tester,
  ) async {
    // Upstream states the rule in words where it has one. The fish marker says
    // the same thing less precisely, so showing both labels the day twice.
    await tester.pumpWidget(
      harness(
        calendarsServing(calendarJson(fasting: 'Fast Day (Fish Allowed)')),
      ),
    );
    await settle(tester);

    expect(find.text('Fast Day (Fish Allowed)'), findsOneWidget);
    expect(find.text('Fish'), findsNothing);
    expect(
      find.text('Great feast'),
      findsOneWidget,
      reason: 'rank still shown',
    );
  });

  testWidgets('gives the Matins gospel its own card', (tester) async {
    // A separate reading from the Gospel, not a variant of it. Conflating them
    // showed the wrong reading on 648 days of the feed.
    await tester.pumpWidget(
      harness(calendarsServing(calendarJson(matinsGospel: true))),
    );
    await settle(tester);

    expect(find.text('Gospel'), findsOneWidget);
    expect(find.text('Matins Gospel'), findsOneWidget);
    expect(find.text('Mark 5:24-34'), findsOneWidget);
    expect(find.text('Luke 1:39-49, 56'), findsOneWidget);
  });

  testWidgets('shows the tone and eothinon the feed publishes', (tester) async {
    await tester.pumpWidget(
      harness(calendarsServing(calendarJson(tone: 7, eothinon: 6))),
    );
    await settle(tester);

    // Named, not numbered: "Tone 7" is not what the seventh tone is called.
    expect(find.text('Grave Tone'), findsOneWidget);
    expect(find.text('Eothinon 6'), findsOneWidget);
  });

  testWidgets('computes the tone and eothinon when the feed omits them', (
    tester,
  ) async {
    // Upstream publishes them on 86 days of 3287, so the computed cycle is
    // what the screen shows almost always.
    await tester.pumpWidget(harness(calendarsServing(calendarJson())));
    await settle(tester);

    // 2026-07-26 is 14 weeks after Thomas Sunday (19 April) and 7 after the
    // Sunday of All Saints (7 June).
    expect(find.text('Grave Tone'), findsOneWidget);
    expect(find.text('Eothinon 8'), findsOneWidget);
  });

  testWidgets('says so plainly when the day is not a fast', (tester) async {
    // An empty slot is ambiguous between there being no fast and our not
    // knowing, which are not the same answer for someone checking.
    // 2026-07-26 is a Sunday outside every season.
    await tester.pumpWidget(harness(calendarsServing(calendarJson())));
    await settle(tester);

    expect(find.text('No fast'), findsOneWidget);
  });

  testWidgets('names an ordinary Wednesday as a fast day', (tester) async {
    await tester.pumpWidget(
      harness(calendarsServing(calendarJson()), date: DateTime(2026, 10, 14)),
    );
    await settle(tester);

    expect(find.text('Fast day'), findsOneWidget);
  });

  testWidgets('falls back to the computed fast season past the feed', (
    tester,
  ) async {
    // 2026-11-20 is inside the Nativity Fast and beyond the feed's end, so
    // there is no published rule to use.
    await tester.pumpWidget(
      harness(calendarsServing(calendarJson()), date: DateTime(2026, 11, 20)),
    );
    await settle(tester);

    expect(find.text('Nativity Fast'), findsOneWidget);
  });

  testWidgets('prefers the published fasting rule over the computed one', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        calendarsServing(calendarJson(fasting: 'Fast Day (Fish Allowed)')),
      ),
    );
    await settle(tester);

    expect(find.text('Fast Day (Fish Allowed)'), findsOneWidget);
  });

  testWidgets('offers the rule the hour belongs to, under the day facts', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        calendarsServing(calendarJson()),
        date: DateTime(2026, 7, 26, 8),
        prayers: const {
          'res/prayers/morning_en.md': '# Morning Prayers\n\nAmen.\n',
        },
      ),
    );
    await settle(tester);

    expect(find.text('Pray now'), findsOne);
    expect(find.text('Morning'), findsOne);

    // Below everything the day *is* — the commemoration and where the day sits
    // in the year — rather than above it.
    final button = tester.getTopLeft(find.text('Pray now')).dy;
    expect(
      button,
      greaterThan(
        tester.getTopLeft(find.text('Paraskeve the Righteous Martyr').first).dy,
      ),
    );
    expect(
      button,
      greaterThan(tester.getTopLeft(find.text('105 days after Pascha')).dy),
      reason: 'under the tone and Pascha strip, not between it and the header',
    );
  });

  testWidgets('leaves the day alone outside those hours', (tester) async {
    await tester.pumpWidget(
      harness(
        calendarsServing(calendarJson()),
        date: DateTime(2026, 7, 26, 16),
        prayers: const {
          'res/prayers/morning_en.md': '# Morning Prayers\n\nAmen.\n',
        },
      ),
    );
    await settle(tester);

    expect(find.text('Pray now'), findsNothing);
  });

  testWidgets('shows the distance from Pascha even with a full day', (
    tester,
  ) async {
    // Computed rather than fetched, so it is present in every state and the
    // no-data screen keeps the same shape as this one.
    await tester.pumpWidget(harness(calendarsServing(calendarJson())));
    await settle(tester);

    expect(find.text('105 days after Pascha'), findsOneWidget);
  });
}
