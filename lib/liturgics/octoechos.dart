// The two weekly cycles that hang off Pascha: the eight Octoechos tones and
// the eleven resurrectional Matins gospels.
//
// Both anchors were checked against every day the feed publishes one: the tone
// matched 86 of 86 and the eothinon 84 of 84, where the other plausible
// anchors matched none. Do not change one without re-running that table.

import 'paschalion.dart';

/// The Octoechos tone for [date], 1 to 8, restarting at Thomas Sunday.
///
/// Null through Bright Week, where the Octoechos is set aside and each day has
/// its own proper texts, so reporting a tone would be inventing one.
int? toneFor(DateTime date) {
  final start = _cycleStart(date, MovableFeast.thomasSunday);
  if (start == null) return null;
  return (_weeksBetween(start, date) % 8) + 1;
}

/// Which of the eleven resurrectional Matins gospels is appointed, 1 to 11,
/// restarting at the Sunday of All Saints.
///
/// Where the cycle stands, not that one is read: through Great Lent and the
/// Pentecostarion the Sunday Matins gospel is proper to the day instead.
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
