// orthocal.info's JSON API, which is where the old calendar comes from.
//
// GOARCH publishes the new calendar only. orthocal computes both, has no end
// date, and states the fasting rule as two numbers rather than a sentence. It
// publishes English only, which is why the Julian calendar is English only.
//
// `stories`, the lives of the saints, is deliberately not read: orthocal has
// it by permission rather than under a licence, and this pipeline republishes
// what it reads. See CLAUDE.md.

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
  const OrthocalSource();

  /// Facts rather than parameters: there is no second safe value. A Gregorian
  /// one would write over GOARCH's own file.
  @override
  String get language => 'en';

  @override
  CalendarStyle get style => CalendarStyle.julian;

  static const _tradition = Tradition.greek;

  String get _base =>
      'https://orthocal.info/api/${_tradition.name}/${style.name}';

  @override
  String get label => '$language.${style.name}';

  @override
  String get attribution => '$_base/';

  /// Fetches a month at a time and keys every day by the date requested.
  ///
  /// [to] is obeyed rather than clamped: the source has no end of its own, so
  /// the bound is the orchestrator's `buildHorizonDays`.
  @override
  Future<ParsedCalendar> load({
    required String from,
    required String to,
    required bool useCache,
  }) async {
    final start = DateTime.parse(from);
    final end = DateTime.parse(to);

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
            'orthocal.${_tradition.name}.${style.name}.'
            '${month.year}-${month.month}.json',
        label: label,
        useCache: useCache,
      );

      for (final entry in parseMonth(body, month, findings).entries) {
        // The caller trims to the window too, but a month is fetched whole and
        // the last one runs past `to`, so this keeps the file's own `end`
        // honest rather than leaving it a fortnight long.
        if (entry.value.date.isAfter(end)) continue;
        days[entry.key] = entry.value;
      }
    }

    // The API computes every day it is asked for, so there is no equivalent of
    // the feed's LAST-MODIFIED: nothing upstream has a date of last change.
    return (days: days, sourceUpdatedAt: null, findings: findings);
  }

  /// One month's response, keyed by the Gregorian date of each entry.
  ///
  /// **By position, never by the response's own date, which is the Julian
  /// one**: asking `/julian/2026/1/7/` returns the Nativity as 2025-12-25, so
  /// keying on it shifts the calendar thirteen days. Position is then the only
  /// thing giving the date, hence the length check.
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

    final days = <String, CalendarDay>{};
    for (var i = 0; i < entries.length; i++) {
      final date = DateTime(month.year, month.month, i + 1);
      days[Calendar.dateKey(date)] = dayFrom(date, entries[i], findings);
    }
    return days;
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

    final (readings, eothinon) = _readings(json);

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
      fastAllowance: _allowance(json, findings, date),
      // 0 is the sentinel for no tone, and rendering it would read as "Tone 0".
      tone: switch (json['tone'] as int?) {
        0 || null => null,
        final tone => tone,
      },
      eothinon: eothinon,
      epistle: readings[_Slot.epistle],
      gospel: readings[_Slot.gospel],
      matinsGospel: readings[_Slot.matinsGospel],
      oldTestament: readings[_Slot.oldTestament],
    );
  }

  /// The four readings the schema has room for, and the eothinon.
  ///
  /// One pass: the eothinon is carried in the Matins gospel's *name*, so it
  /// falls out of the same match. Upstream names far more than four — the
  /// Hours, the Passion gospels — and those are dropped rather than reported,
  /// there being nowhere in `CalendarDay` for them. Vespers readings are the
  /// Old Testament prophecies, which is the one mapping the names hide.
  static (Map<_Slot, Reading>, int?) _readings(Map<String, dynamic> json) {
    final readings = <_Slot, Reading>{};
    int? eothinon;

    for (final entry in (json['readings'] as List<dynamic>? ?? const [])) {
      final reading = entry as Map<String, dynamic>;
      final source = reading['source'] as String? ?? '';
      final matins = _matinsGospel.firstMatch(source);
      final slot = matins != null ? _Slot.matinsGospel : _named[source];
      if (slot == null) continue;

      // The first where upstream appoints two: a Sunday carries its own
      // epistle and the saint's, and the day's own comes first.
      readings.putIfAbsent(
        slot,
        () => Reading(reference: reading['display'] as String? ?? ''),
      );
      // A feast's own Matins gospel is written without a number and is not one
      // of the eleven, so it fills the slot without supplying an eothinon.
      eothinon ??= int.tryParse(matins?.group(1) ?? '');
    }

    return (readings, eothinon);
  }

  static final _matinsGospel = RegExp(r'^(?:(\d+)\w{2} )?Matins Gospel$');

  /// The reading names that map straight to a slot.
  static const _named = {
    'Epistle': _Slot.epistle,
    'Gospel': _Slot.gospel,
    'Vespers': _Slot.oldTestament,
  };

  /// What the day permits, from the two numbers upstream states.
  ///
  /// `fast_level` is the season and `fast_exception` the allowance. Null where
  /// the day does not fast, which is what the feed says by publishing no rule.
  ///
  /// Three Slavic distinctions the Greek usage does not draw flatten into
  /// [FastAllowance.wineAndOil]: wine without oil, caviar, and "Strict Fast
  /// (Wine and Oil)". About one day a year each.
  static FastAllowance? _allowance(
    Map<String, dynamic> json,
    List<Finding> findings,
    DateTime date,
  ) {
    final level = json['fast_level'] as int? ?? 0;
    final exception = json['fast_exception'] as int? ?? 0;

    if (exception == 11) return FastAllowance.free;
    if (level == 0) return null;

    final allowance = switch (exception) {
      0 || 9 || 10 => FastAllowance.strict,
      1 || 3 || 5 || 6 || 8 => FastAllowance.wineAndOil,
      2 || 4 => FastAllowance.fish,
      7 => FastAllowance.dairyEggsAndFish,
      _ => null,
    };
    if (allowance != null) return allowance;

    // An exception upstream has added. Reported rather than guessed at, and
    // under the same kind as an unmapped rule from the feed: both mean the
    // day's published rule is not the one upstream states. The strict fallback
    // is the safe direction to be wrong in.
    findings.add((
      date: Calendar.dateKey(date),
      line:
          'fast_exception $exception (${json['fast_exception_desc']}) '
          'under fast_level ${json['fast_level']}',
      kind: FindingKind.unmappedFastingRule,
    ));
    return FastAllowance.strict;
  }

  /// Day 0 of the next month is the last day of this one.
  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;
}

/// Which of `CalendarDay`'s four reading slots a reading belongs in.
enum _Slot { epistle, gospel, matinsGospel, oldTestament }
