// Converting between the two calendars.
//
// Both directions go through the Julian Day Number rather than adding 13, so
// the gap widens in 2100 on its own. Narrow in purpose: both calendars keep
// Pascha on the same day, so only the fixed feasts convert.
//
// **What comes back is calendar fields, not an instant.** Do not subtract two
// of them, and do not hand one to `DateFormat` for a weekday — that would be a
// fortnight out. Read the weekday off the Gregorian date, which both agree on.

/// The Julian Day Number of a Gregorian calendar date.
int _julianDayFromGregorian(int year, int month, int day) {
  final a = (14 - month) ~/ 12;
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day +
      (153 * m + 2) ~/ 5 +
      365 * y +
      y ~/ 4 -
      y ~/ 100 +
      y ~/ 400 -
      32045;
}

/// The Julian Day Number of a Julian calendar date.
int _julianDayFromJulian(int year, int month, int day) {
  final a = (14 - month) ~/ 12;
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - 32083;
}

/// The Gregorian calendar date of a Julian Day Number.
DateTime _gregorianFromJulianDay(int julianDay) {
  final a = julianDay + 32044;
  final b = (4 * a + 3) ~/ 146097;
  final c = a - (146097 * b) ~/ 4;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - (1461 * d) ~/ 4;
  final m = (5 * e + 2) ~/ 153;

  return DateTime(
    100 * b + d - 4800 + m ~/ 10,
    m + 3 - 12 * (m ~/ 10),
    e - (153 * m + 2) ~/ 5 + 1,
  );
}

/// The Julian calendar date of a Julian Day Number.
DateTime _julianFromJulianDay(int julianDay) {
  final c = julianDay + 32082;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - (1461 * d) ~/ 4;
  final m = (5 * e + 2) ~/ 153;

  return DateTime(
    d - 4800 + m ~/ 10,
    m + 3 - 12 * (m ~/ 10),
    e - (153 * m + 2) ~/ 5 + 1,
  );
}

/// The Julian calendar date falling on the same day as Gregorian [date].
///
/// Gregorian 7 January 2026 is Julian 25 December 2025, which is why the
/// Nativity is kept on the 7th by anyone following the old calendar.
DateTime julianDateOf(DateTime date) => _julianFromJulianDay(
  _julianDayFromGregorian(date.year, date.month, date.day),
);

/// The Gregorian calendar date falling on the same day as Julian [date].
DateTime gregorianDateOf(DateTime date) => _gregorianFromJulianDay(
  _julianDayFromJulian(date.year, date.month, date.day),
);
