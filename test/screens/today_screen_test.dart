import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/screens/today_screen.dart';
import 'package:prosefchi/services/calendar_repository.dart';

import '../support/memory_calendar_store.dart';

String calendarJson({
  String language = 'en',
  String title = 'Paraskeve the Righteous Martyr',
  List<String> saints = const [
    'Paraskeve the Righteous Martyr',
    'Hermolaos the Holy Martyr',
  ],
  List<String> marks = const ['majorFeast', 'fish'],
  String gospelReference = 'Mark 5:24-34',
}) => jsonEncode({
  'language': language,
  'source': 'https://example.test/feed.ics',
  'generatedAt': '2026-07-26',
  'start': '2026-07-01',
  'end': '2026-08-31',
  'days': {
    '2026-07-26': {
      'title': title,
      'saints': saints,
      'marks': marks,
      'gospel': {
        'reference': gospelReference,
        'text':
            'At that time, a great crowd followed him and thronged about him.',
      },
    },
  },
});

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` cannot be used here: it runs until no frame is scheduled,
/// and the loading spinner schedules one forever, so it spins until its own
/// timeout instead of returning.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  CalendarRepository repositoryServing(String? body) => CalendarRepository(
    baseUrl: Uri.parse('https://example.test/'),
    client: MockClient(
      (_) async => body == null
          ? http.Response('nope', 503)
          : http.Response.bytes(utf8.encode(body), 200),
    ),
    store: MemoryCalendarStore(),
  );

  Widget harness(
    CalendarRepository repository, {
    Locale locale = const Locale('en'),
    DateTime? date,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TodayScreen(
      repository: repository,
      date: date ?? DateTime(2026, 7, 26),
    ),
  );

  testWidgets('shows the commemoration, marks and reading', (tester) async {
    await tester.pumpWidget(harness(repositoryServing(calendarJson())));
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
    expect(find.text('Fish'), findsOneWidget);
  });

  testWidgets('renders Greek labels under the el locale', (tester) async {
    await tester.pumpWidget(
      harness(
        repositoryServing(
          calendarJson(
            language: 'el',
            title: 'Παρασκευή η Οσιομάρτυς',
            saints: const ['Παρασκευή η Οσιομάρτυς', 'Ερμόλαος ο Ιερομάρτυς'],
            marks: const ['fish'],
            gospelReference: 'Κατὰ Μᾶρκον 5:24-34',
          ),
        ),
        locale: const Locale('el'),
      ),
    );
    await settle(tester);

    expect(find.text('Σήμερα'), findsOneWidget);
    expect(find.text('Ευαγγέλιο'), findsOneWidget);
    expect(find.text('Ιχθύς'), findsOneWidget);
    expect(find.text('Παρασκευή η Οσιομάρτυς'), findsWidgets);
  });

  testWidgets('falls back to computed data when nothing is cached', (
    tester,
  ) async {
    // A first launch with no network: the app must still say something rather
    // than show an error, because the Paschalion needs no data at all.
    await tester.pumpWidget(harness(repositoryServing(null)));
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
      harness(repositoryServing(calendarJson()), date: DateTime(2026, 9, 15)),
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
        repositoryServing(
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
    await tester.pumpWidget(harness(repositoryServing(calendarJson())));
    await settle(tester);

    const passage =
        'At that time, a great crowd followed him and thronged about him.';
    expect(find.text('Mark 5:24-34'), findsOneWidget);
    expect(find.text(passage), findsNothing);

    await tester.tap(find.text('Gospel'));
    await settle(tester);

    expect(find.text(passage), findsOneWidget);
  });

  testWidgets('shows the distance from Pascha even with a full day', (
    tester,
  ) async {
    // Computed rather than fetched, so it is present in every state and the
    // no-data screen keeps the same shape as this one.
    await tester.pumpWidget(harness(repositoryServing(calendarJson())));
    await settle(tester);

    expect(find.text('105 days after Pascha'), findsOneWidget);
  });
}
