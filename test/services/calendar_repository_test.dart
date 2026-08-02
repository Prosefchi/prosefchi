import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosefchi/models/calendar.dart';
import 'package:prosefchi/services/calendar_repository.dart';

import '../support/calendar_fixture.dart';

import '../support/memory_calendar_store.dart';

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

      expect(
        await repository.load('en', style: CalendarStyle.gregorian),
        isNull,
      );
      expect(
        await repository.dayFor(
          calendarFixtureDate,
          'en',
          style: CalendarStyle.gregorian,
        ),
        isNull,
      );
    });

    test('reads back what refresh stored, without the network', () async {
      var requests = 0;
      final repository = repositoryWith(
        MockClient((_) async {
          requests++;
          return http.Response(
            calendarJson(sourceUpdatedAt: '2025-05-29T23:50:14.000Z'),
            200,
          );
        }),
      );

      expect(
        await repository.refresh('en', style: CalendarStyle.gregorian),
        isTrue,
      );
      repository.clearCache();

      final calendar = await repository.load(
        'en',
        style: CalendarStyle.gregorian,
      );
      expect(calendar, isNotNull);
      expect(
        calendar!.forDate(calendarFixtureDate)?.title,
        'Paraskeve the Righteous Martyr',
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

      await repository.refresh('en', style: CalendarStyle.gregorian);
      await repository.refresh('en', style: CalendarStyle.gregorian);

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

      expect(
        await repository.refresh('en', style: CalendarStyle.gregorian),
        isTrue,
      );
      expect(
        await repository.refresh('en', style: CalendarStyle.gregorian),
        isFalse,
      );
      expect(
        await repository.load('en', style: CalendarStyle.gregorian),
        isNotNull,
      );
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

      expect(
        await repository.refresh('en', style: CalendarStyle.gregorian),
        isTrue,
      );

      serveGarbage = true;
      expect(
        await repository.refresh('en', style: CalendarStyle.gregorian),
        isFalse,
      );

      repository.clearCache();
      expect(
        (await repository.load(
          'en',
          style: CalendarStyle.gregorian,
        ))?.forDate(calendarFixtureDate)?.title,
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

      expect(
        await repository.refresh('en', style: CalendarStyle.gregorian),
        isTrue,
      );

      offline = true;
      expect(
        await repository.refresh('en', style: CalendarStyle.gregorian),
        isFalse,
      );

      repository.clearCache();
      expect(
        (await repository.load(
          'en',
          style: CalendarStyle.gregorian,
        ))?.forDate(calendarFixtureDate)?.title,
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

      await repository.refresh('el', style: CalendarStyle.gregorian);
      repository.clearCache();

      expect(
        (await repository.load(
          'el',
          style: CalendarStyle.gregorian,
        ))?.forDate(calendarFixtureDate)?.title,
        title,
      );
    });

    test('returns false on a server error and stores nothing', () async {
      final repository = repositoryWith(
        MockClient((_) async => http.Response('nope', 503)),
      );

      expect(
        await repository.refresh('en', style: CalendarStyle.gregorian),
        isFalse,
      );
      expect(
        await repository.load('en', style: CalendarStyle.gregorian),
        isNull,
      );
      expect(store.entries, isEmpty);
    });
  });

  group('switching language', () {
    test('fetches the new language without discarding the old', () async {
      // Changing language must refetch, but the previous language is still
      // paid for and still correct. Throwing it away would cost the user a
      // download to switch back, offline or not.
      final repository = repositoryWith(
        MockClient(
          (request) async => http.Response(
            calendarJson(
              language: request.url.path.contains('.el.') ? 'el' : 'en',
            ),
            200,
            headers: {'etag': '"${request.url.path}"'},
          ),
        ),
      );

      await repository.refresh('en', style: CalendarStyle.gregorian);
      await repository.refresh('el', style: CalendarStyle.gregorian);

      expect(
        store.entries.keys,
        containsAll([
          'calendar.en.gregorian.json',
          'calendar.el.gregorian.json',
        ]),
      );
      expect(
        await repository.load('en', style: CalendarStyle.gregorian),
        isNotNull,
      );
      expect(
        await repository.load('el', style: CalendarStyle.gregorian),
        isNotNull,
      );
    });

    test('switching back costs a 304 rather than a download', () async {
      final bodies = <String>[];
      final repository = repositoryWith(
        MockClient((request) async {
          if (request.headers.containsKey('If-None-Match')) {
            return http.Response('', 304);
          }
          bodies.add(request.url.path);
          return http.Response(
            calendarJson(),
            200,
            headers: {'etag': '"${request.url.path}"'},
          );
        }),
      );

      await repository.refresh('en', style: CalendarStyle.gregorian);
      await repository.refresh('el', style: CalendarStyle.gregorian);
      await repository.refresh('en', style: CalendarStyle.gregorian);

      expect(bodies, [
        '/calendar.en.gregorian.json',
        '/calendar.el.gregorian.json',
      ], reason: 'the second visit to en is conditional');
    });
  });

  test('exposes Greek as el, the code intl expects', () {
    expect(supportedLanguages, contains('el'));
    expect(supportedLanguages, isNot(contains('gr')));
  });

  group('the calendar style names the file', () {
    test('asks for the file the chosen calendar is published as', () async {
      final asked = <String>[];
      final repository = repositoryWith(
        MockClient((request) async {
          asked.add(request.url.path);
          return http.Response(calendarJson(), 200);
        }),
      );

      await repository.refresh('en', style: CalendarStyle.gregorian);
      await repository.refresh('en', style: CalendarStyle.julian);

      expect(asked, [
        '/calendar.en.gregorian.json',
        '/calendar.en.julian.json',
      ]);
    });

    test('keeps the two apart in the store and the cache', () async {
      // Same language, two files. Sharing a key would serve whichever was
      // fetched last under both settings.
      final repository = repositoryWith(
        MockClient(
          (request) async => request.url.path.contains('julian')
              ? http.Response(calendarJson(title: 'Old calendar day'), 200)
              : http.Response(calendarJson(title: 'New calendar day'), 200),
        ),
      );

      await repository.refresh('en', style: CalendarStyle.gregorian);
      await repository.refresh('en', style: CalendarStyle.julian);

      expect(
        (await repository.load(
          'en',
          style: CalendarStyle.gregorian,
        ))?.forDate(calendarFixtureDate)?.title,
        'New calendar day',
      );
      expect(
        (await repository.load(
          'en',
          style: CalendarStyle.julian,
        ))?.forDate(calendarFixtureDate)?.title,
        'Old calendar day',
      );
    });

    test('never asks for a combination nothing publishes', () async {
      // Only English has a Julian file. A Greek reader who chooses the old
      // calendar falls back to the computed layer, and should not pay for a
      // round trip that can only 404 on every launch to find that out.
      var requests = 0;
      final repository = repositoryWith(
        MockClient((_) async {
          requests++;
          return http.Response(calendarJson(), 200);
        }),
      );

      expect(
        await repository.refresh('el', style: CalendarStyle.julian),
        isFalse,
      );
      expect(requests, 0);
      expect(await repository.load('el', style: CalendarStyle.julian), isNull);
    });
  });
}
