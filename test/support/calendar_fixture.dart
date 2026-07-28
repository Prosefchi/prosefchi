import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosefchi/services/calendar_repository.dart';

import 'memory_calendar_store.dart';

/// One published day, as the built calendar JSON.
///
/// Shared rather than copied per test file. The feed's window is a thing that
/// moves — upstream tops it up roughly yearly — so a second copy drifts out of
/// range on its own, and a screen test whose date falls outside the window
/// renders "no entry for this day" while still passing whatever it asserted.
String calendarJson({
  String language = 'en',
  String title = 'Paraskeve the Righteous Martyr',
  List<String> saints = const [
    'Paraskeve the Righteous Martyr',
    'Hermolaos the Holy Martyr',
  ],
  List<String> marks = const ['majorFeast'],
  String gospelReference = 'Mark 5:24-34',
  String? fasting,
  bool matinsGospel = false,
  int? tone,
  int? eothinon,
  String? sourceUpdatedAt,
}) => jsonEncode({
  'language': language,
  'source': 'https://example.test/feed.ics',
  'generatedAt': '2026-07-26',
  // When upstream last changed, which only the repository tests read.
  'sourceUpdatedAt': ?sourceUpdatedAt,
  'start': '2026-07-01',
  'end': '2026-08-31',
  'days': {
    '2026-07-26': {
      'title': title,
      'saints': saints,
      'marks': marks,
      'fasting': ?fasting,
      'tone': ?tone,
      'eothinon': ?eothinon,
      if (matinsGospel)
        'matinsGospel': {
          'reference': 'Luke 1:39-49, 56',
          'text': 'At that time Mary arose and went into the hill country.',
        },
      'gospel': {
        'reference': gospelReference,
        'text':
            'At that time, a great crowd followed him and thronged about him.',
      },
    },
  },
});

/// The date [calendarJson] publishes, which a screen test has to be asked for.
final calendarFixtureDate = DateTime(2026, 7, 26);

/// A repository serving [body], or a 503 when it is null.
///
/// The three parts go together for a reason worth not rediscovering: a real
/// `FileCalendarStore` reaches path_provider and a real `http.Client` reaches
/// the network, and under `FakeAsync` both hang until the test times out
/// rather than failing.
CalendarRepository calendarsServing(String? body) => CalendarRepository(
  baseUrl: Uri.parse('https://example.test/'),
  client: MockClient(
    (_) async => body == null
        ? http.Response('nope', 503)
        : http.Response.bytes(utf8.encode(body), 200),
  ),
  store: MemoryCalendarStore(),
);

/// A repository that serves nothing, for a test that never reaches the feed.
///
/// The same thing as [calendarsServing] with no body — kept as a name because
/// "offline" is what the tests using it mean.
CalendarRepository offlineCalendars() => calendarsServing(null);
