import 'dart:convert';
import 'dart:ui' show Locale;
import 'dart:io' show HttpStatus;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/calendar.dart';
import 'calendar_store.dart';

// `supportedLanguages` lives on the Flutter-free side so the website can read
// it too, but every screen asks this file for it, so it is re-exported rather
// than moved out from under them.
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

/// Where the published calendar is served from.
///
/// GitHub Pages by deliberate choice. A shipped build cannot be repointed, so
/// if this ever has to move the plan is to publish from both hosts, ship an
/// update that switches over, and retire this one only once the old installs
/// have drained.
final defaultCalendarBaseUrl = Uri.parse(
  'https://prosefchi.github.io/prosefchi/',
);

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

  /// The stored calendar for [language], or null if none has been kept yet.
  ///
  /// Never touches the network.
  Future<Calendar?> load(String language) =>
      _cache[language] ??= _readStored(language);

  /// The entry for [date], or null if nothing is stored or the calendar does
  /// not reach that far.
  Future<CalendarDay?> dayFor(DateTime date, String language) async =>
      (await load(language))?.forDate(date);

  /// Fetches [language] from the network, storing it if it changed.
  ///
  /// Returns true only when new data was stored. A conditional request means
  /// the usual outcome is a bodiless 304, so calling this on every launch is
  /// cheap.
  Future<bool> refresh(String language) async {
    try {
      // Both are independent, and neither reads the calendar body: a 304 with
      // no stored copy would leave us with nothing, so the conditional request
      // is only sent when there is something to fall back on.
      final (etag, stored) = await (
        _store.read(_etagName(language)),
        _store.exists(_jsonName(language)),
      ).wait;

      final response = await _client.get(
        _baseUrl.resolve(_jsonName(language)),
        headers: {'If-None-Match': ?(stored ? etag : null)},
      );

      if (response.statusCode == HttpStatus.notModified) return false;
      if (response.statusCode != HttpStatus.ok) {
        debugPrint('calendar: $language refresh got ${response.statusCode}');
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

      await _store.write(_jsonName(language), body);
      final newEtag = response.headers['etag'];
      if (newEtag != null) {
        await _store.write(_etagName(language), newEtag);
      } else {
        await _store.delete(_etagName(language));
      }

      _cache[language] = Future.value(calendar);
      return true;
    } on Object catch (error) {
      // Offline, DNS failure, TLS problem, malformed payload: all the same
      // outcome. Keep whatever is already stored.
      debugPrint('calendar: $language refresh failed ($error)');
      return false;
    }
  }

  Future<Calendar?> _readStored(String language) async {
    try {
      final raw = await _store.read(_jsonName(language));
      if (raw == null) return null;
      return Calendar.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      debugPrint('calendar: could not read stored $language ($error)');
      return null;
    }
  }

  static String _jsonName(String language) => Calendar.fileName(language);

  static String _etagName(String language) => 'calendar.$language.etag';

  /// Drops in-memory calendars so the next [load] re-reads from the store.
  void clearCache() => _cache.clear();

  void dispose() => _client.close();
}
