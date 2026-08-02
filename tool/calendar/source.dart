// What every calendar source has to produce, so the tool can treat them alike.
//
// One of our files is built from exactly one source, and the source decides
// nothing about how it is rendered: it hands back `CalendarDay`s carrying a
// `FastAllowance` rather than a rule in words, so a calendar built from an
// English-only source can still be read in Greek. That normalisation is the
// whole reason this boundary exists — see the CLAUDE.md section on the data
// pipeline.

import 'package:prosefchi/models/calendar.dart';

/// The days a source yielded, plus what it could not account for.
typedef ParsedCalendar = ({
  Map<String, CalendarDay> days,
  DateTime? sourceUpdatedAt,

  /// Lines the parser recognised as meaningful but could not classify.
  ///
  /// Reported at build time and never shown. Loud on purpose: the previous
  /// one of these put the Matins reading in the Gospel slot on 648 days.
  List<String> unparsed,
});

/// A published calendar one of our files can be built from.
abstract interface class CalendarSource {
  /// The language the days come out in, as an ISO 639-1 code.
  String get language;

  /// Where the data came from, kept in [Calendar.source] for attribution.
  String get attribution;

  /// Everything the source has for [from]..[to] inclusive, and possibly more.
  ///
  /// The range is what a source needs to know to fetch at all — an API queried
  /// a month at a time cannot be asked for its whole span — but it is not a
  /// promise about what comes back. A feed that arrives whole returns whole,
  /// and the caller trims either way, so the window and the runway warning are
  /// applied identically however the days were obtained.
  Future<ParsedCalendar> load({
    required String from,
    required String to,
    required bool useCache,
  });
}
