// The two weekly cycles that hang off Pascha: the eight Octoechos tones and
// the eleven resurrectional Matins gospels.
//
// Upstream publishes both, but only on 86 days of a nine-year feed, so they
// have to be computed to be useful. Both anchors here were checked against
// every one of those days rather than taken from memory: the tone matched 86
// of 86 and the eothinon 84 of 84, while the other plausible anchors matched
// none. See test/liturgics/octoechos_test.dart.

import 'paschalion.dart';

/// The Octoechos tone for [date], 1 to 8, or null where there is none.
///
/// The cycle restarts at Tone 1 on Thomas Sunday and advances every week.
///
/// Null through Bright Week, from Pascha to the eve of Thomas Sunday: the
/// Octoechos is set aside for those days and each has its own proper texts, so
/// reporting a tone would be inventing one.
int? toneFor(DateTime date) {
  final start = _cycleStart(date, MovableFeast.thomasSunday);
  if (start == null) return null;
  return (_weeksBetween(start, date) % 8) + 1;
}

/// Which of the eleven resurrectional Matins gospels is appointed, 1 to 11.
///
/// The cycle restarts at the first on the Sunday of All Saints and advances
/// every week.
///
/// This says where the cycle stands, not that one is read: through Great Lent
/// and the Pentecostarion the Sunday Matins gospel is proper to the day
/// instead, and [CalendarDay.matinsGospel] is what actually says which reading
/// is appointed.
int eothinonFor(DateTime date) {
  final start =
      _cycleStart(date, MovableFeast.allSaints) ??
      // Between Pascha and All Saints the cycle from the previous year is
      // still the one in force.
      MovableFeast.allSaints.inYear(date.year - 1);
  return (_weeksBetween(start, date) % 11) + 1;
}

/// The most recent occurrence of [feast] on or before [date], or null if the
/// only candidate is later in the same paschal year.
DateTime? _cycleStart(DateTime date, MovableFeast feast) {
  final thisYear = feast.inYear(date.year);
  if (!date.isBefore(thisYear)) return thisYear;

  final lastYear = feast.inYear(date.year - 1);
  // Before Pascha the previous year's cycle is still running. On or after it
  // but before the feast itself, the cycle is between runs.
  return date.isBefore(orthodoxPascha(date.year)) ? lastYear : null;
}

/// Whole weeks from [from] to [to], counting the week containing [from] as 0.
int _weeksBetween(DateTime from, DateTime to) => daysBetween(from, to) ~/ 7;
