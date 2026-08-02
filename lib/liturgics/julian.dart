// Converting between the two calendars.
//
// The Julian calendar runs behind the Gregorian by 13 days from 1900 to 2100
// and the gap grows by a day roughly every century, so nothing here hardcodes
// it: both directions go through the Julian Day Number, which is a plain count
// of days and knows nothing about either calendar's leap rules.
//
// What this is *for* is narrow. Old and New Calendarists keep Pascha on the
// same day — the Revised Julian calendar kept the Julian paschalion — so the
// whole movable cycle is shared and none of it converts. Only the fixed
// feasts and the fasts tied to them fall on a different civil day, and those
// are what `fasting.dart` reads through here.
//
// A `DateTime` returned by [julianDateOf] carries a Julian year, month and day
// in a Gregorian type. It is a set of calendar fields and not an instant: do
// not subtract two of them, and do not hand one to `DateFormat` expecting a
// correct weekday. The weekday is the one thing both calendars agree on
// anyway, so read it from the Gregorian date.

/// The Julian Day Number of a Gregorian calendar date.
int julianDayFromGregorian(int year, int month, int day) {
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
int julianDayFromJulian(int year, int month, int day) {
  final a = (14 - month) ~/ 12;
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - 32083;
}

/// The Gregorian calendar date of a Julian Day Number.
DateTime gregorianFromJulianDay(int julianDay) {
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
DateTime julianFromJulianDay(int julianDay) {
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
DateTime julianDateOf(DateTime date) => julianFromJulianDay(
  julianDayFromGregorian(date.year, date.month, date.day),
);

/// The Gregorian calendar date falling on the same day as Julian [date].
DateTime gregorianDateOf(DateTime date) => gregorianFromJulianDay(
  julianDayFromJulian(date.year, date.month, date.day),
);
