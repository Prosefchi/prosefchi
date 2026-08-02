// What every calendar source has to produce, so the tool can treat them alike.
//
// A source decides nothing about rendering: it hands back a `FastAllowance`
// rather than a rule in words. That normalisation is why this boundary is
// here, and it is what lets a source's language differ from the reader's.

import 'package:prosefchi/models/calendar.dart';

/// Why a source left something unaccounted for.
///
/// Told apart by the type rather than a prefix on the message, because one is
/// cosmetic and the other silently changes what the app says about a day.
enum FindingKind {
  /// A line matching nothing we know, usually a feast name upstream put where
  /// the fasting rule goes. Nothing is lost: it is simply not shown.
  unrecognised,

  /// A fasting rule the source states and we could not map.
  ///
  /// The day then publishes something other than what upstream says: nothing
  /// at all, which reads as not fasting, or a safe fallback. The one to act on.
  unmappedFastingRule,
}

/// Something a source could not account for, and where.
typedef Finding = ({String date, String line, FindingKind kind});

/// The days a source yielded, plus what it could not account for.
typedef ParsedCalendar = ({
  Map<String, CalendarDay> days,
  DateTime? sourceUpdatedAt,

  /// Reported at build time and never shown. Loud on purpose: the previous
  /// one of these put the Matins reading in the Gospel slot on 648 days.
  List<Finding> findings,
});

/// A published calendar one of our files can be built from.
abstract interface class CalendarSource {
  /// The language the days come out in, as an ISO 639-1 code.
  String get language;

  /// Which reckoning these days are for, which names the file.
  CalendarStyle get style;

  /// What to call this source in the build log and the cache. One definition,
  /// because it was briefly three.
  String get label;

  /// Where the data came from, kept in [Calendar.source] for attribution.
  String get attribution;

  /// Everything the source has for [from]..[to] inclusive, and possibly more.
  ///
  /// The range is what an API queried a month at a time needs to fetch at all,
  /// not a promise about what comes back: the caller trims either way, so the
  /// window and the runway warning apply identically to every source.
  Future<ParsedCalendar> load({
    required String from,
    required String to,
    required bool useCache,
  });
}
