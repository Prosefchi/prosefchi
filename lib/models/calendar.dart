// Data model for the liturgical calendar.
//
// Both sides of the pipeline use these types: tool/build_calendar.dart writes
// them via toJson, and the app reads them back with fromJson. One definition
// means the generator and the reader cannot drift apart.

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

  static DayMark? byName(String name) {
    for (final mark in values) {
      if (mark.name == name) return mark;
    }
    return null;
  }

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
    this.fasting,
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
        fasting: json['fasting'] as String?,
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

  /// The fasting rule in words, as upstream states it: "Strict Fast", "Fast
  /// Day (Wine and Oil Allowed)", "Fast Free" and so on.
  ///
  /// Authoritative where it exists, and unambiguous in a way [marks] is not:
  /// the markers only ever record an allowance, so an unmarked day could be a
  /// strict fast or no fast at all. This says which.
  final String? fasting;

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
    if (fasting != null) 'fasting': fasting,
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
  ///
  /// Compares in UTC: a local subtraction spanning a daylight-saving change
  /// loses an hour and truncates to a day short.
  int runwayFrom(DateTime from) => DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

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

  /// The canonical `YYYY-MM-DD` key for [date], ignoring any time component.
  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
