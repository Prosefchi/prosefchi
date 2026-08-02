import 'dart:convert';
import 'dart:ui' show Locale;
import 'dart:io' show HttpStatus;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/calendar.dart';
import '../models/site.dart' show defaultCalendarBaseUrl;
import 'calendar_store.dart';

// Every screen asks this file for the languages, so it is re-exported.
export '../models/calendar.dart' show supportedLanguages;

/// The content language for [locale], clamped to what we actually publish.
///
/// One definition: every screen asks this question and a private copy in each
/// was four places to keep in step.
String languageFor(Locale locale) =>
    supportedLanguages.contains(locale.languageCode)
    ? locale.languageCode
    : supportedLanguages.first;

/// The repository used wherever one is not injected.
///
/// Shared on purpose. Parsing a year of Greek readings is not free and the
/// cache inside a repository is per-instance, so three screens each building
/// their own meant reading and parsing the same stored calendar three times a
/// launch — and leaking two `http.Client`s along with it. Lazily created on
/// first use, and lives as long as the app, so nothing disposes it.
final sharedCalendarRepository = CalendarRepository();

/// Fetches the calendar and keeps it stored between launches.
///
/// Reading and refreshing are deliberately separate. [load] is local and fast,
/// so the UI never waits on a network call to draw; [refresh] is the only thing
/// that touches the network.
///
/// Every failure here is soft. A missing or stale calendar is an ordinary state
/// — a first launch, a lapsed upstream feed, a plane — and callers fall back to
/// the computed liturgical layer rather than showing an error.
class CalendarRepository {
  CalendarRepository({Uri? baseUrl, http.Client? client, CalendarStore? store})
    : _baseUrl = baseUrl ?? defaultCalendarBaseUrl,
      _client = client ?? http.Client(),
      _store = store ?? FileCalendarStore();

  final Uri _baseUrl;
  final http.Client _client;
  final CalendarStore _store;

  /// Parsing a few hundred kilobytes of Greek readings is not free. Holds nulls
  /// too, so a missing calendar is not re-read on every widget rebuild.
  ///
  /// The *future* rather than the value, so that callers arriving while a read
  /// is still in flight wait on it instead of starting their own. A language
  /// switch has two — the Today screen and the reminder refresh — in the same
  /// turn of the event loop.
  final Map<String, Future<Calendar?>> _cache = {};

  /// The stored calendar for [language] and [style], or null if none is kept.
  ///
  /// Never touches the network.
  ///
  /// Null is also the ordinary answer for a combination nothing publishes:
  /// every language has a Gregorian calendar but only English has a Julian
  /// one. Callers already handle it by falling back to the computed layer,
  /// which is what a reader in that position should get.
  Future<Calendar?> load(String language, {required CalendarStyle style}) =>
      _cache[_jsonName(language, style)] ??= _readStored(language, style);

  /// The entry for [date], or null if nothing is stored or the calendar does
  /// not reach that far.
  Future<CalendarDay?> dayFor(
    DateTime date,
    String language, {
    required CalendarStyle style,
  }) async => (await load(language, style: style))?.forDate(date);

  /// Fetches [language] from the network, storing it if it changed.
  ///
  /// Returns true only when new data was stored. A conditional request means
  /// the usual outcome is a bodiless 304, so calling this on every launch is
  /// cheap.
  Future<bool> refresh(String language, {required CalendarStyle style}) async {
    // Nothing publishes every combination, and asking for one that does not
    // exist is a round trip that can only 404 — on every launch, before the
    // day screen gives up waiting on it. The reader falls back to the computed
    // layer, which is what they should get.
    if (!style.isPublishedFor(language)) return false;

    try {
      // Both are independent, and neither reads the calendar body: a 304 with
      // no stored copy would leave us with nothing, so the conditional request
      // is only sent when there is something to fall back on.
      final (etag, stored) = await (
        _store.read(_etagName(language, style)),
        _store.exists(_jsonName(language, style)),
      ).wait;

      final response = await _client.get(
        _baseUrl.resolve(_jsonName(language, style)),
        headers: {'If-None-Match': ?(stored ? etag : null)},
      );

      if (response.statusCode == HttpStatus.notModified) return false;
      if (response.statusCode != HttpStatus.ok) {
        debugPrint(
          'calendar: ${_jsonName(language, style)} got ${response.statusCode}',
        );
        return false;
      }

      // Decode explicitly as UTF-8. `response.body` honours the charset in the
      // Content-Type header and falls back to latin1 when it is absent, which
      // silently mangles polytonic Greek.
      final body = utf8.decode(response.bodyBytes);

      // Parse before storing. A malformed deploy must not overwrite a good
      // stored copy and take the app's offline data down with it.
      final calendar = Calendar.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );

      await _store.write(_jsonName(language, style), body);
      final newEtag = response.headers['etag'];
      if (newEtag != null) {
        await _store.write(_etagName(language, style), newEtag);
      } else {
        await _store.delete(_etagName(language, style));
      }

      _cache[_jsonName(language, style)] = Future.value(calendar);
      return true;
    } on Object catch (error) {
      // Offline, DNS failure, TLS problem, malformed payload: all the same
      // outcome. Keep whatever is already stored.
      debugPrint('calendar: ${_jsonName(language, style)} failed ($error)');
      return false;
    }
  }

  Future<Calendar?> _readStored(String language, CalendarStyle style) async {
    try {
      final raw = await _store.read(_jsonName(language, style));
      if (raw == null) return null;
      return Calendar.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      debugPrint(
        'calendar: cannot read ${_jsonName(language, style)} ($error)',
      );
      return null;
    }
  }

  static String _jsonName(String language, CalendarStyle style) =>
      Calendar.fileName(language, style: style);

  /// Derived from the file name so the two cannot drift.
  static String _etagName(String language, CalendarStyle style) =>
      '${_jsonName(language, style)}.etag';

  /// Drops in-memory calendars so the next [load] re-reads from the store.
  void clearCache() => _cache.clear();

  void dispose() => _client.close();
}
