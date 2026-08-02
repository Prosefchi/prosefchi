// orthocal.info's JSON API, which is where the old calendar comes from.
//
// GOARCH publishes the new calendar only, so nothing in its feeds can answer
// what an Old Calendarist keeps today. orthocal computes both, has no end date
// at all — the API accepts any year from 1583 to 4099 — and states the fasting
// rule as two numbers rather than a sentence, which is what lets its days be
// read in a language it does not publish.
//
// It publishes English only. That is why the Julian calendar is built for
// English alone; see the CLAUDE.md section on the old calendar.
//
// Licence: the code is MIT and the service is offered "with no strings
// attached", asking only to be told about usage. The lives of the saints it
// carries are used *by permission* from Abbamoses.com rather than licensed, so
// the `stories` field is deliberately not read here — this pipeline
// republishes what it reads.

import 'dart:convert';

import 'package:prosefchi/models/calendar.dart';

import 'fetch.dart';
import 'source.dart';

/// Which typikon the day is reckoned by.
///
/// `greek` is the Antiochian and Greek Archdiocese usage and so the one that
/// matches the rest of this app; `slavic` is the OCA and ROCOR usage. Upstream
/// still marks the Greek tradition beta.
enum Tradition { slavic, greek }

/// One orthocal calendar, as a source the tool can build a file from.
class OrthocalSource implements CalendarSource {
  const OrthocalSource({
    this.language = 'en',
    this.style = CalendarStyle.julian,
    this.tradition = Tradition.greek,
    this.horizonDays = 400,
  });

  @override
  final String language;

  @override
  final CalendarStyle style;

  final Tradition tradition;

  /// How far past today to build, in days.
  ///
  /// The source itself has no end, so without a bound the default `--to` of
  /// 9999-12-31 would ask for four thousand years a month at a time. This is
  /// the runway the published file carries instead, and a little over a year
  /// keeps the whole build to fourteen requests.
  final int horizonDays;

  String get _base =>
      'https://orthocal.info/api/${tradition.name}/${style.name}';

  @override
  String get attribution => '$_base/';

  /// Fetches a month at a time and keys every day by the date requested.
  ///
  /// **The response's own `year`/`month`/`day` are the Julian date and must
  /// not be used as the key.** Asking `/julian/2026/1/7/` — a Gregorian date —
  /// returns the Nativity, reported as 2025-12-25. Keying on what comes back
  /// would shift the whole calendar thirteen days, which reads as the app
  /// simply being wrong about the date rather than as a parsing bug.
  ///
  /// So the position in the month's list is the day of that month, and the
  /// count is checked against the month's length rather than trusted.
  @override
  Future<ParsedCalendar> load({
    required String from,
    required String to,
    required bool useCache,
  }) async {
    final start = DateTime.parse(from);
    final end = _earlier(DateTime.parse(to), _horizonEnd());

    final days = <String, CalendarDay>{};
    final findings = <Finding>[];

    for (
      var month = DateTime(start.year, start.month);
      !month.isAfter(DateTime(end.year, end.month));
      month = DateTime(month.year, month.month + 1)
    ) {
      final body = await fetch(
        '$_base/${month.year}/${month.month}/',
        key:
            'orthocal.${tradition.name}.${style.name}.'
            '${month.year}-${month.month}.json',
        label: '$language.${style.name}',
        useCache: useCache,
      );

      for (final entry in parseMonth(body, month, findings).entries) {
        final date = DateTime.parse(entry.key);
        if (date.isBefore(start) || date.isAfter(end)) continue;
        days[entry.key] = entry.value;
      }
    }

    // The API computes every day it is asked for, so there is no equivalent of
    // the feed's LAST-MODIFIED: nothing upstream has a date of last change.
    return (days: days, sourceUpdatedAt: null, findings: findings);
  }

  /// One month's response, keyed by the Gregorian date of each entry.
  ///
  /// The key comes from the entry's *position*, because the response states
  /// the Julian date and using that would move the whole calendar. The count
  /// is checked against the month's length rather than assumed: if upstream
  /// ever returns a short month, position stops meaning the day and every
  /// date after the gap would be silently wrong.
  Map<String, CalendarDay> parseMonth(
    String body,
    DateTime month,
    List<Finding> findings,
  ) {
    final entries = (jsonDecode(body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final length = daysInMonth(month.year, month.month);
    if (entries.length != length) {
      throw StateError(
        '${month.year}-${month.month}: got ${entries.length} days for a '
        '$length-day month, so position no longer gives the date',
      );
    }

    return {
      for (var i = 0; i < entries.length; i++)
        Calendar.dateKey(DateTime(month.year, month.month, i + 1)): dayFrom(
          DateTime(month.year, month.month, i + 1),
          entries[i],
          findings,
        ),
    };
  }

  /// Public, like the GOARCH helpers, so `test/tool/` can reach it.
  CalendarDay dayFrom(
    DateTime date,
    Map<String, dynamic> json,
    List<Finding> findings,
  ) {
    final titles = (json['titles'] as List<dynamic>? ?? const [])
        .cast<String>();
    final saints = (json['saints'] as List<dynamic>? ?? const [])
        .cast<String>();

    Reading? first(String source) {
      for (final entry in (json['readings'] as List<dynamic>? ?? const [])) {
        final reading = entry as Map<String, dynamic>;
        if (_sourceKind(reading['source'] as String? ?? '') != source) continue;
        return Reading(reference: reading['display'] as String? ?? '');
      }
      return null;
    }

    return CalendarDay(
      date: date,
      title: json['summary_title'] as String? ?? '',
      // Mirrors the feed's shape, where the day's own title heads the list and
      // the fixed commemorations follow it.
      saints: [...titles, ...saints],
      marks: [
        // 6 and up are the great feasts; the lower levels are typikon service
        // ranks with no equivalent here. The allowance markers have no
        // equivalent either, being what fastAllowance already carries.
        if ((json['feast_level'] as int? ?? 0) >= 6) DayMark.majorFeast,
      ],
      fastAllowance: _allowance(json, findings, Calendar.dateKey(date)),
      // 0 is the sentinel for no tone, and rendering it would read as "Tone 0".
      tone: switch (json['tone'] as int?) {
        0 || null => null,
        final tone => tone,
      },
      eothinon: _eothinon(json),
      epistle: first('epistle'),
      gospel: first('gospel'),
      matinsGospel: first('matinsGospel'),
      oldTestament: first('oldTestament'),
    );
  }

  /// Which of our four slots a reading belongs in, or the empty string.
  ///
  /// Upstream names far more than four — the Hours, the twelve Passion
  /// gospels, the Great Blessing of Waters — and those are dropped rather than
  /// reported: they are perfectly well understood, there is simply nowhere in
  /// `CalendarDay` for them. The Vespers readings are the Old Testament
  /// prophecies and are the one non-obvious mapping.
  static String _sourceKind(String source) {
    if (source == 'Epistle') return 'epistle';
    if (source == 'Gospel') return 'gospel';
    if (source == 'Vespers') return 'oldTestament';
    if (_matinsGospel.hasMatch(source)) return 'matinsGospel';
    return '';
  }

  static final _matinsGospel = RegExp(r'^(?:(\d+)\w{2} )?Matins Gospel$');

  /// The eothinon, taken from the name of the Matins gospel.
  ///
  /// Upstream carries it as "11th Matins Gospel" rather than as a field, and
  /// writes a bare "Matins Gospel" where a feast has one of its own, which is
  /// not one of the eleven and so is no eothinon at all.
  static int? _eothinon(Map<String, dynamic> json) {
    for (final entry in (json['readings'] as List<dynamic>? ?? const [])) {
      final match = _matinsGospel.firstMatch(
        (entry as Map<String, dynamic>)['source'] as String? ?? '',
      );
      if (match?.group(1) case final number?) return int.parse(number);
    }
    return null;
  }

  /// What the day permits, from the two numbers upstream states.
  ///
  /// `fast_level` is the season and `fast_exception` the allowance, and the
  /// day fasts unless the level is 0 or the exception lifts it outright. Null
  /// where it does not fast and nothing was lifted, which is an ordinary day
  /// and the same thing the feed says by publishing no rule.
  ///
  /// Upstream draws finer distinctions than the five here, and three of them
  /// flatten: wine without oil and the caviar allowance both arrive as
  /// [FastAllowance.wineAndOil], and "Strict Fast (Wine and Oil)" is recorded
  /// by what it permits rather than by its name. Those are Slavic distinctions
  /// the Greek usage does not draw, and each falls on about one day a year.
  static FastAllowance? _allowance(
    Map<String, dynamic> json,
    List<Finding> findings,
    String date,
  ) {
    final level = json['fast_level'] as int? ?? 0;
    final exception = json['fast_exception'] as int? ?? 0;

    if (exception == 11) return FastAllowance.free;
    if (level == 0) return null;

    return switch (exception) {
      0 || 9 || 10 => FastAllowance.strict,
      1 || 3 || 5 || 6 || 8 => FastAllowance.wineAndOil,
      2 || 4 => FastAllowance.fish,
      7 => FastAllowance.dairyEggsAndFish,
      _ => () {
        // An exception upstream has added. Reported rather than guessed at,
        // and under the same kind as an unmapped rule from the feed: both mean
        // the day's rule is not the one published.
        findings.add((
          date: date,
          line:
              'fast_exception $exception (${json['fast_exception_desc']}) '
              'under fast_level ${json['fast_level']}',
          kind: FindingKind.unmappedFastingRule,
        ));
        return FastAllowance.strict;
      }(),
    };
  }

  DateTime _horizonEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + horizonDays);
  }

  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  /// Day 0 of the next month is the last day of this one.
  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;
}
