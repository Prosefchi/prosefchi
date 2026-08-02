// Data model for the liturgical calendar.
//
// Both sides of the pipeline use these types: tool/build_calendar.dart writes
// them via toJson, and the app reads them back with fromJson. One definition
// means the generator and the reader cannot drift apart.

import '../liturgics/paschalion.dart';

/// Languages the calendar is published in, as ISO 639-1 codes.
const supportedLanguages = ['en', 'el'];

/// A marker GOARCH prefixes to a day's title.
///
/// These encode the fasting allowance and the rank of the feast. They appear
/// only in the event summary and never in the commemorations list, so the
/// saints arrive clean and only the title needs splitting.
///
/// These mark *allowances* only, so an unmarked day is ambiguous between a
/// strict fast and no fast at all. [CalendarDay.fasting] resolves that: on the
/// days it is present upstream states the rule outright, and it should be
/// preferred over these.
enum DayMark {
  /// A great feast.
  majorFeast('☦'),

  /// Wine and oil permitted.
  wineAndOil('🍇'),

  /// Fish permitted.
  fish('🐟'),

  /// Dairy permitted, as through Cheesefare week.
  dairy('🧀');

  const DayMark(this.symbol);

  /// The bare codepoint, without the variation selector upstream appends.
  final String symbol;

  static DayMark? byName(String name) => values.asNameMap()[name];

  /// Splits the markers off a raw title.
  ///
  /// The variation selector (U+FE0F) has to be removed along with the symbol,
  /// or the cleaned title keeps a stray invisible character that shows up as
  /// a leading space.
  static ({String title, List<DayMark> marks}) split(String raw) {
    final found = <DayMark>[];
    var text = raw;
    for (final mark in values) {
      if (!text.contains(mark.symbol)) continue;
      found.add(mark);
      text = text.replaceAll('${mark.symbol}️', '').replaceAll(mark.symbol, '');
    }
    return (title: text.trim(), marks: found);
  }
}

/// What a fast day permits.
///
/// This is the vocabulary the whole pipeline branches on, and it is upstream's
/// own rather than an invention: GOARCH states the rule in words, six phrasings
/// in English and nine in Greek, and across the 1917 days of the feed that
/// carry one the two languages never disagree and every phrasing collapses to
/// one of these five. The extra Greek strings are spelling variants of the same
/// rule, monotonic beside polytonic.
///
/// Deliberately the *allowance* and not the season. What is permitted on a fast
/// day depends on the rank of the feast and cannot be computed from a date; the
/// season is `fastSeasonFor` in `liturgics/fasting.dart` and needs no data at
/// all. Publishing this and computing that is the same division the rest of the
/// app draws.
///
/// A source that draws finer distinctions has to map into these — see
/// `tool/calendar/` — which is what lets a calendar built from one source be
/// rendered in a language that source does not publish.
enum FastAllowance {
  /// Nothing lifted: no oil, no wine.
  strict,

  wineAndOil,

  fish,

  /// Cheesefare week, where everything but meat is kept.
  dairyEggsAndFish,

  /// The fast lifted entirely.
  free;

  static FastAllowance? byName(String? name) =>
      name == null ? null : values.asNameMap()[name];

  /// Whether a day under this allowance fasts at all.
  bool get fasts => this != FastAllowance.free;
}

/// An appointed scripture reading.
///
/// [text] is absent on the rare entries where upstream gives only a citation.
class Reading {
  const Reading({required this.reference, this.text});

  factory Reading.fromJson(Map<String, dynamic> json) => Reading(
    reference: json['reference'] as String,
    text: json['text'] as String?,
  );

  final String reference;
  final String? text;

  Map<String, dynamic> toJson() => {
    'reference': reference,
    if (text != null) 'text': text,
  };
}

/// One day's commemorations and readings.
///
/// Roughly 9% of days carry no appointed readings, so [epistle] and [gospel]
/// are routinely null rather than exceptionally so.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.title,
    this.saints = const [],
    this.marks = const [],
    this.fastAllowance,
    this.tone,
    this.eothinon,
    this.epistle,
    this.gospel,
    this.matinsGospel,
    this.oldTestament,
  });

  factory CalendarDay.fromJson(String date, Map<String, dynamic> json) =>
      CalendarDay(
        date: DateTime.parse(date),
        title: json['title'] as String? ?? '',
        saints: (json['saints'] as List<dynamic>? ?? const [])
            .cast<String>()
            .toList(),
        marks: (json['marks'] as List<dynamic>? ?? const [])
            .cast<String>()
            .map(DayMark.byName)
            .nonNulls
            .toList(),
        fastAllowance: FastAllowance.byName(json['fastAllowance'] as String?),
        tone: json['tone'] as int?,
        eothinon: json['eothinon'] as int?,
        epistle: _reading(json['epistle']),
        gospel: _reading(json['gospel']),
        matinsGospel: _reading(json['matinsGospel']),
        oldTestament: _reading(json['oldTestament']),
      );

  static Reading? _reading(Object? json) =>
      json == null ? null : Reading.fromJson(json as Map<String, dynamic>);

  final DateTime date;

  /// The primary commemoration, used as the headline on the Today page.
  final String title;

  /// All commemorations for the day, including [title].
  final List<String> saints;

  /// Fasting allowances and feast rank, as marked upstream.
  final List<DayMark> marks;

  /// What the day's fast permits, where the source states a rule.
  ///
  /// Resolved when the calendar is built, so no reader ever interprets a
  /// source's wording. Unambiguous in a way [marks] is not: the markers only
  /// ever record an allowance, so an unmarked day could be a strict fast or no
  /// fast at all. This says which.
  ///
  /// Null on the roughly 42% of days no rule is stated for, which are ordinary
  /// days. The weekday fast still applies to them and is computed, not
  /// published — see `isFastDay`.
  final FastAllowance? fastAllowance;

  /// Whether the day fasts at all.
  ///
  /// False both when no rule is stated and when the rule lifts the fast, which
  /// are different facts with the same answer to this question.
  bool get fasts => fastAllowance?.fasts ?? false;

  /// The Octoechos tone, 1 to 8, where upstream publishes it.
  ///
  /// Rarely: 86 days of the feed. The cycle is computable for any date, and
  /// those days are what the computation was checked against.
  final int? tone;

  /// The eothinon, 1 to 11: which of the eleven resurrectional Matins gospels
  /// is appointed. Published as rarely as [tone], and computable the same way.
  final int? eothinon;

  final Reading? epistle;
  final Reading? gospel;

  /// The resurrectional gospel read at Matins, appointed on roughly a fifth of
  /// days. A different reading from [gospel], not a variant of it.
  final Reading? matinsGospel;

  final Reading? oldTestament;

  bool get hasReadings =>
      epistle != null ||
      gospel != null ||
      matinsGospel != null ||
      oldTestament != null;

  bool get isMajorFeast => marks.contains(DayMark.majorFeast);

  Map<String, dynamic> toJson() => {
    'title': title,
    if (saints.isNotEmpty) 'saints': saints,
    if (marks.isNotEmpty) 'marks': [for (final mark in marks) mark.name],
    if (fastAllowance != null) 'fastAllowance': fastAllowance!.name,
    if (tone != null) 'tone': tone,
    if (eothinon != null) 'eothinon': eothinon,
    if (epistle != null) 'epistle': epistle!.toJson(),
    if (gospel != null) 'gospel': gospel!.toJson(),
    if (matinsGospel != null) 'matinsGospel': matinsGospel!.toJson(),
    if (oldTestament != null) 'oldTestament': oldTestament!.toJson(),
  };
}

/// A bounded window of days for a single language.
///
/// The upstream feed has a hard end date and simply stops rather than rolling
/// forward, so [end] is load-bearing: callers must handle dates beyond it by
/// falling back to the computed liturgical layer.
class Calendar {
  const Calendar({
    required this.language,
    required this.source,
    required this.generatedAt,
    required this.start,
    required this.end,
    required this.days,
    this.sourceUpdatedAt,
  });

  factory Calendar.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as Map<String, dynamic>;
    return Calendar(
      language: json['language'] as String,
      source: json['source'] as String,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      sourceUpdatedAt: switch (json['sourceUpdatedAt']) {
        final String value => DateTime.parse(value),
        _ => null,
      },
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      days: {
        for (final entry in rawDays.entries)
          entry.key: CalendarDay.fromJson(
            entry.key,
            entry.value as Map<String, dynamic>,
          ),
      },
    );
  }

  final String language;

  /// The upstream feed this was built from, kept for attribution.
  final String source;

  /// When this file was built, which is every CI run whether or not anything
  /// changed. For "is my data current" use [sourceUpdatedAt] instead.
  final DateTime generatedAt;

  /// The latest `LAST-MODIFIED` across the upstream feed, or null if it carried
  /// none.
  ///
  /// Upstream is topped up in bulk roughly once a year rather than edited
  /// continuously, so this moves rarely and is the honest answer to when the
  /// commemorations themselves last changed.
  final DateTime? sourceUpdatedAt;

  final DateTime start;
  final DateTime end;

  /// Keyed by ISO date (`2026-07-25`).
  final Map<String, CalendarDay> days;

  /// The day's entry, or null if [date] falls outside the covered window.
  CalendarDay? forDate(DateTime date) => days[dateKey(date)];

  bool covers(DateTime date) {
    final key = dateKey(date);
    return key.compareTo(dateKey(start)) >= 0 &&
        key.compareTo(dateKey(end)) <= 0;
  }

  /// Days of coverage left after [from]. Negative once the feed has lapsed.
  int runwayFrom(DateTime from) => daysBetween(from, end);

  Map<String, dynamic> toJson() => {
    'language': language,
    'source': source,
    'generatedAt': dateKey(generatedAt),
    if (sourceUpdatedAt != null)
      'sourceUpdatedAt': sourceUpdatedAt!.toUtc().toIso8601String(),
    'start': dateKey(start),
    'end': dateKey(end),
    'days': {
      for (final key in days.keys.toList()..sort()) key: days[key]!.toJson(),
    },
  };

  /// What a published calendar is named, for one language.
  static String fileName(String language) => 'calendar.$language.json';

  /// The canonical `YYYY-MM-DD` key for [date], ignoring any time component.
  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
