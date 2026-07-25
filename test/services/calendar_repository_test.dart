import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosefchi/services/calendar_repository.dart';

import '../support/memory_calendar_store.dart';

String calendarJson({
  String language = 'en',
  String title = 'Dormition of St. Anna',
  String start = '2026-07-01',
  String end = '2026-07-31',
}) => jsonEncode({
  'language': language,
  'source': 'https://example.test/feed.ics',
  'generatedAt': '2026-07-26',
  'sourceUpdatedAt': '2025-05-29T23:50:14.000Z',
  'start': start,
  'end': end,
  'days': {
    '2026-07-25': {
      'title': title,
      'saints': [title, 'Olympias the Deaconess'],
      'marks': ['fish'],
      'epistle': {'reference': 'Galatians 4:22-27', 'text': 'Brethren...'},
    },
  },
});

void main() {
  late MemoryCalendarStore store;

  setUp(() => store = MemoryCalendarStore());

  CalendarRepository repositoryWith(MockClient client) => CalendarRepository(
    baseUrl: Uri.parse('https://example.test/'),
    client: client,
    store: store,
  );

  group('load', () {
    test('returns null before anything has been fetched', () async {
      // A first launch. The app must come up and fall back to the computed
      // layer rather than failing.
      final repository = repositoryWith(
        MockClient((_) async => http.Response('', 500)),
      );

      expect(await repository.load('en'), isNull);
      expect(await repository.dayFor(DateTime(2026, 7, 25), 'en'), isNull);
    });

    test('reads back what refresh stored, without the network', () async {
      var requests = 0;
      final repository = repositoryWith(
        MockClient((_) async {
          requests++;
          return http.Response(calendarJson(), 200);
        }),
      );

      expect(await repository.refresh('en'), isTrue);
      repository.clearCache();

      final calendar = await repository.load('en');
      expect(calendar, isNotNull);
      expect(
        calendar!.forDate(DateTime(2026, 7, 25))?.title,
        'Dormition of St. Anna',
      );
      expect(calendar.sourceUpdatedAt, DateTime.utc(2025, 5, 29, 23, 50, 14));
      expect(requests, 1, reason: 'load must not hit the network');
    });
  });

  group('refresh', () {
    test('sends If-None-Match once an ETag is known', () async {
      final sent = <String?>[];
      final repository = repositoryWith(
        MockClient((request) async {
          sent.add(request.headers['If-None-Match']);
          return http.Response(
            calendarJson(),
            200,
            headers: {'etag': 'W/"abc123"'},
          );
        }),
      );

      await repository.refresh('en');
      await repository.refresh('en');

      expect(sent, [null, 'W/"abc123"']);
    });

    test('treats 304 as success with nothing to do', () async {
      final repository = repositoryWith(
        MockClient(
          (request) async => request.headers.containsKey('If-None-Match')
              ? http.Response('', 304)
              : http.Response(calendarJson(), 200, headers: {'etag': '"v1"'}),
        ),
      );

      expect(await repository.refresh('en'), isTrue);
      expect(await repository.refresh('en'), isFalse);
      expect(await repository.load('en'), isNotNull);
    });

    test('keeps the stored copy when the server returns garbage', () async {
      // A broken deploy must not take the app's offline data down with it.
      var serveGarbage = false;
      final repository = repositoryWith(
        MockClient(
          (_) async => serveGarbage
              ? http.Response('<html>502 Bad Gateway</html>', 200)
              : http.Response(calendarJson(title: 'Good Data'), 200),
        ),
      );

      expect(await repository.refresh('en'), isTrue);

      serveGarbage = true;
      expect(await repository.refresh('en'), isFalse);

      repository.clearCache();
      expect(
        (await repository.load('en'))?.forDate(DateTime(2026, 7, 25))?.title,
        'Good Data',
      );
    });

    test('keeps the stored copy when the network is down', () async {
      var offline = false;
      final repository = repositoryWith(
        MockClient((_) async {
          if (offline) throw const SocketException('Network is unreachable');
          return http.Response(calendarJson(title: 'Cached'), 200);
        }),
      );

      expect(await repository.refresh('en'), isTrue);

      offline = true;
      expect(await repository.refresh('en'), isFalse);

      repository.clearCache();
      expect(
        (await repository.load('en'))?.forDate(DateTime(2026, 7, 25))?.title,
        'Cached',
      );
    });

    test('decodes polytonic Greek as UTF-8 whatever the Content-Type', () async {
      // `http`'s Response.body falls back to latin1 when the header carries no
      // charset, which mangles Greek. The repository must decode bytes itself.
      const title = 'Κοίμησις Ἁγίας Ἄννης, Μητρὸς τῆς Θεοτόκου';
      final repository = repositoryWith(
        MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(calendarJson(language: 'el', title: title)),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      await repository.refresh('el');
      repository.clearCache();

      expect(
        (await repository.load('el'))?.forDate(DateTime(2026, 7, 25))?.title,
        title,
      );
    });

    test('returns false on a server error and stores nothing', () async {
      final repository = repositoryWith(
        MockClient((_) async => http.Response('nope', 503)),
      );

      expect(await repository.refresh('en'), isFalse);
      expect(await repository.load('en'), isNull);
      expect(store.entries, isEmpty);
    });
  });

  test('exposes Greek as el, the code intl expects', () {
    expect(supportedLanguages, contains('el'));
    expect(supportedLanguages, isNot(contains('gr')));
  });
}
