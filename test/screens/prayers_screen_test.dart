import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/screens/occasion_ui.dart';
import 'package:prosefchi/screens/prayers_screen.dart';
import 'package:prosefchi/screens/reading_scrollbar.dart';
import 'package:prosefchi/services/prayer_repository.dart';
import '../support/pump.dart';
import '../support/fake_bundle.dart';

const morning = '''
# Morning Prayers

> On rising from sleep, make the sign of the Cross.

## The Beginning

In the name of the Father, and of the Son, and of the Holy Spirit. Amen.
''';

const placeholderMidday = '''
# Midday Prayers

> [Awaiting text: the midday rule.]
''';

const attributed = '''
# Morning Prayers

Amen.

---

[Source](https://example.org/rule/)
''';

Widget harness(
  Map<String, String> assets, {
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: PrayersScreen(repository: PrayerRepository(bundle: FakeBundle(assets))),
);

void main() {
  testWidgets('lists every rule', (tester) async {
    await tester.pumpWidget(harness({'res/prayers/morning_en.md': morning}));
    await settle(tester);

    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Midday'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);
  });

  testWidgets('gives every rule its own icon', (tester) async {
    surface(tester, const Size(1170, 2600));

    await tester.pumpWidget(harness({'res/prayers/morning_en.md': morning}));
    await settle(tester);

    final icons = PrayerOccasion.values.map(occasionIcon).toSet();
    expect(
      icons,
      hasLength(PrayerOccasion.values.length),
      reason: 'a shared icon would make two rules look like the same thing',
    );
    for (final icon in icons) {
      expect(find.byIcon(icon), findsOneWidget);
    }
  });

  testWidgets('groups the rules the way the reminders screen does', (
    tester,
  ) async {
    await tester.pumpWidget(harness({'res/prayers/morning_en.md': morning}));
    await settle(tester);

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Liturgy'), findsOneWidget);
  });

  testWidgets('marks a rule with no text unavailable and does not open it', (
    tester,
  ) async {
    // Group headings make the list taller than the default 800x600 surface,
    // and a ListView does not build rows it cannot show.
    surface(tester, const Size(1170, 2600));

    // A stub must never be presented as though it were an abbreviated prayer.
    await tester.pumpWidget(
      harness({
        'res/prayers/morning_en.md': morning,
        'res/prayers/midday_en.md': placeholderMidday,
      }),
    );
    await settle(tester);

    expect(
      find.text('Not yet available'),
      findsNWidgets(PrayerOccasion.values.length - 1),
      reason: 'every rule but morning is unavailable',
    );

    await tester.tap(find.text('Midday'));
    await settle(tester);

    expect(find.text('Midday Prayers'), findsNothing);
  });

  testWidgets('opens a rule that has real text alongside a marked gap', (
    tester,
  ) async {
    // The morning rule holds the Trisagion and a gap awaiting the rest. The
    // gap must not withhold the part that is ready.
    const partial = '$morning\n> [Awaiting text: the rest of the rule.]\n';
    await tester.pumpWidget(harness({'res/prayers/morning_en.md': partial}));
    await settle(tester);

    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(find.text('The Beginning'), findsOneWidget);
    expect(find.text('[Awaiting text: the rest of the rule.]'), findsOneWidget);
  });

  testWidgets('opens a rule and renders its blocks', (tester) async {
    await tester.pumpWidget(harness({'res/prayers/morning_en.md': morning}));
    await settle(tester);

    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(find.text('Morning Prayers'), findsOneWidget);
    expect(find.text('The Beginning'), findsOneWidget);
    expect(
      find.text('On rising from sleep, make the sign of the Cross.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'In the name of the Father, and of the Son, and of the Holy Spirit. Amen.',
      ),
      findsOneWidget,
    );
  });

  group('the scrollbar', () {
    String longRule() {
      final b = StringBuffer('# Evening Prayers\n\n');
      for (var i = 0; i < 120; i++) {
        b.write('## Section $i\n\n');
        b.write(
          'Glory to the Father and the Son and the Holy Spirit, now and '
          'forever and to the ages of ages. Amen. Lord, have mercy.\n\n',
        );
      }
      return b.toString();
    }

    ScrollPosition positionOf(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position;

    /// Pumps a long rule, optionally wrapped in Material's bar instead, and
    /// leaves it scrolled with the pill showing.
    Future<ScrollPosition> openLongRule(WidgetTester tester) async {
      surface(tester, narrowSurface);
      final set = PrayerSet.parse(longRule());
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PrayerScreen(set: set),
        ),
      );
      await tester.pump();
      final position = positionOf(tester);
      position.jumpTo(2000);
      // The bar fades in, and its own hit test refuses a transparent thumb.
      await tester.pump(const Duration(milliseconds: 300));
      return position;
    }

    testWidgets('measures the rule exactly, so the pill does not drift', (
      tester,
    ) async {
      // A lazy viewport reports an extent estimated from the children it has
      // built, which changes as it goes; the thumb is drawn from that number.
      // See the note in prayers_screen.dart for the measurements.
      final position = await openLongRule(tester);

      final extents = <double>{position.maxScrollExtent};
      for (var i = 0; i < 6; i++) {
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -900),
        );
        await tester.pump();
        extents.add(position.maxScrollExtent);
      }

      expect(
        extents,
        hasLength(1),
        reason: 'the rule changed height while being scrolled through',
      );
    });

    group('the progress bubble', () {
      Future<void> pumpBubble(
        WidgetTester tester,
        double fraction, {
        TextScaler scaler = TextScaler.noScaling,
      }) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: scaler),
            child: Center(child: ScrollProgressBubble(fraction: fraction)),
          ),
        ),
      );

      testWidgets('reads as a whole percentage of the way through', (
        tester,
      ) async {
        for (final (fraction, shown) in [
          (0.0, '0%'),
          (0.304, '30%'),
          (0.5, '50%'),
          (1.0, '100%'),
        ]) {
          await pumpBubble(tester, fraction);
          expect(find.text(shown), findsOneWidget);
        }
      });

      testWidgets('stays a fixed circle whatever the text size', (
        tester,
      ) async {
        // It is chrome saying where the reader is, not text to be read, and
        // the circle is a fixed size — a figure that grew with the setting
        // would spill out of it.
        await pumpBubble(tester, 0.5);
        final plain = tester.getSize(find.byType(ScrollProgressBubble));
        final plainText = tester.getSize(find.text('50%'));

        await pumpBubble(tester, 0.5, scaler: const TextScaler.linear(1.8));

        expect(tester.getSize(find.byType(ScrollProgressBubble)), plain);
        expect(tester.getSize(find.text('50%')), plainText);
      });
    });

    testWidgets('gives the rule a bar whose track is inert', (tester) async {
      // Wiring, not behaviour, and knowingly so. What ReadingScrollbar changes
      // is that a tap on the track no longer pages the rule, and that could
      // not be made to fail here by any route tried: through a gesture, and by
      // calling handleTrackTapDown directly, with the override removed, the
      // rule still did not move — Material's paging does not reach a
      // ScrollPosition under flutter_test. So an assertion that it "did not
      // scroll" is green either way and would be worse than nothing.
      //
      // This at least fails if the screen is put back on a plain Scrollbar.
      // The behaviour itself needs a device, and rests on CupertinoScrollbar
      // using the same override for the same purpose on iOS.
      await openLongRule(tester);

      expect(find.byType(ReadingScrollbar), findsOneWidget);
    });
  });

  testWidgets('renders a source attribution under a rule', (tester) async {
    await tester.pumpWidget(harness({'res/prayers/morning_en.md': attributed}));
    await settle(tester);

    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(find.byType(Divider), findsOneWidget);
    expect(
      find.text('Source'),
      findsOneWidget,
      reason: 'the label, not the bracketed form around it',
    );
    expect(find.textContaining('https://'), findsNothing);
  });

  testWidgets('labels the rules in Greek under the el locale', (tester) async {
    // Group headings make the list taller than the default 800x600 surface,
    // and a ListView does not build rows it cannot show.
    surface(tester, const Size(1170, 2600));

    await tester.pumpWidget(
      harness({
        'res/prayers/morning_el.md': '# Πρωινὲς Προσευχές\n\nἈμήν.\n',
      }, locale: const Locale('el')),
    );
    await settle(tester);

    expect(find.text('Προσευχές'), findsOneWidget);
    expect(find.text('Πρωί'), findsOneWidget);
    expect(
      find.text('Δεν είναι ακόμη διαθέσιμο'),
      findsNWidgets(PrayerOccasion.values.length - 1),
    );
  });
}
