// The fasting seasons, computed from the Paschalion.
//
// The feed states the rule outright on most days it covers, and
// `CalendarDay.fasting` should be preferred wherever it is present: it is what
// the Archdiocese actually publishes, and it accounts for exceptions no set of
// rules here would capture. This exists for the days beyond the feed's end,
// where otherwise the app could say nothing at all.

import '../models/calendar.dart' show CalendarStyle;
import 'paschalion.dart';

/// A season of fasting in the Orthodox year.
enum FastSeason {
  /// The week before Great Lent, from the Monday after Meatfare Sunday.
  ///
  /// Meat is given up but dairy, eggs and fish are kept, and unusually that
  /// holds on the Wednesday and Friday too, which is why it has to be modelled
  /// rather than left to the weekday rule.
  cheesefare,

  /// From Clean Monday to Holy Saturday.
  greatLent,

  /// From the Monday after All Saints to the eve of Saints Peter and Paul, so
  /// its length varies with the date of Pascha and it disappears entirely when
  /// Pascha falls late.
  apostles,

  /// The first fortnight of August, to the Dormition.
  dormition,

  /// The forty days to the Nativity.
  nativity,
}

/// A week the fast is lifted even on Wednesday and Friday.
enum FastFreeWeek {
  /// From Pascha to the eve of Thomas Sunday.
  bright,

  /// The week after Pentecost, before the Apostles' Fast begins.
  afterPentecost,

  /// The week following the Sunday of the Publican and the Pharisee.
  publicanAndPharisee,

  /// From the Nativity to Theophany, with the eve of Theophany excepted.
  christmastide,
}

/// The fasting season [date] falls in, or null if it falls in none.
///
/// [style] moves the fixed boundaries and nothing else: the Dormition and
/// Nativity fasts and the end of the Apostles' Fast. The rest hang off Pascha,
/// which both calendars keep on the same day.
FastSeason? fastSeasonFor(
  DateTime date, {
  CalendarStyle style = CalendarStyle.gregorian,
}) => _fastSeason(date, style.dateOf(date), style);

/// [fixed] is [date] as [style] counts it, passed in because [isFastDay] has
/// already converted before it calls either of these.
FastSeason? _fastSeason(DateTime date, DateTime fixed, CalendarStyle style) {
  if (_within(
    date,
    addDays(MovableFeast.meatfareSunday.inYear(date.year), 1),
    MovableFeast.cheesefareSunday.inYear(date.year),
  )) {
    return FastSeason.cheesefare;
  }

  if (_within(
    date,
    MovableFeast.cleanMonday.inYear(date.year),
    MovableFeast.holySaturday.inYear(date.year),
  )) {
    return FastSeason.greatLent;
  }

  // Movable at one end and fixed at the other, so the one season compared in
  // both spaces. On the old calendar the end is 11 July, which is why the fast
  // is 13 days longer there and can no longer vanish to a late Pascha.
  final apostlesStart = MovableFeast.apostlesFastBegins.inYear(date.year);
  final apostlesEnd = style.civilDateOf(DateTime(fixed.year, 6, 28));
  if (!apostlesStart.isAfter(apostlesEnd) &&
      _within(date, apostlesStart, apostlesEnd)) {
    return FastSeason.apostles;
  }

  if (_within(fixed, DateTime(fixed.year, 8), DateTime(fixed.year, 8, 14))) {
    return FastSeason.dormition;
  }

  if (_within(
    fixed,
    DateTime(fixed.year, 11, 15),
    DateTime(fixed.year, 12, 24),
  )) {
    return FastSeason.nativity;
  }

  return null;
}

/// Days that fast whatever the weekday and whatever season they fall in.
///
/// Fixed to the calendar rather than to Pascha: the Beheading of the Forerunner,
/// the Exaltation of the Cross, and the eves of Theophany and the Nativity.
const _fixedFastDays = [(8, 29), (9, 14), (1, 5), (12, 24)];

/// The fast-free week [date] falls in, or null if it falls in none.
///
/// Only Christmastide moves with [style]; the other three hang off Pascha.
FastFreeWeek? fastFreeWeekFor(
  DateTime date, {
  CalendarStyle style = CalendarStyle.gregorian,
}) => _fastFreeWeek(date, style.dateOf(date));

FastFreeWeek? _fastFreeWeek(DateTime date, DateTime fixed) {
  final year = date.year;

  if (_within(date, orthodoxPascha(year), addDays(orthodoxPascha(year), 6))) {
    return FastFreeWeek.bright;
  }
  if (_within(
    date,
    MovableFeast.pentecost.inYear(year),
    MovableFeast.allSaints.inYear(year),
  )) {
    return FastFreeWeek.afterPentecost;
  }
  if (_within(
    date,
    MovableFeast.publicanAndPharisee.inYear(year),
    addDays(MovableFeast.publicanAndPharisee.inYear(year), 6),
  )) {
    return FastFreeWeek.publicanAndPharisee;
  }
  // Straddles the new year, hence two windows. The eve of Theophany on the 5th
  // is a strict fast inside it, excluded above by _fixedFastDays.
  if (_within(
        fixed,
        DateTime(fixed.year, 12, 25),
        DateTime(fixed.year, 12, 31),
      ) ||
      _within(fixed, DateTime(fixed.year), DateTime(fixed.year, 1, 6))) {
    return FastFreeWeek.christmastide;
  }
  return null;
}

/// Whether [date] is a fast day at all.
///
/// True inside a fasting season, and on the Wednesdays and Fridays of the rest
/// of the year, which are fast days in their own right. False through the
/// fast-free weeks, which lift even those.
///
/// This is the coarse question. What is permitted on a fast day varies with
/// the season, the day of the week and the rank of the feast, and is exactly
/// what `CalendarDay.fasting` answers where it is available.
bool isFastDay(DateTime date, {CalendarStyle style = CalendarStyle.gregorian}) {
  // Converted once and shared, not three times: this runs sixty times per
  // reminder refresh and a local DateTime resolves the timezone per call.
  final fixed = style.dateOf(date);
  if (_fixedFastDays.contains((fixed.month, fixed.day))) return true;
  if (_fastFreeWeek(date, fixed) != null) return false;
  if (_fastSeason(date, fixed, style) != null) return true;
  // The weekday is the one thing the two calendars never disagree about, so it
  // is read from the real date rather than the converted one.
  return date.weekday == DateTime.wednesday || date.weekday == DateTime.friday;
}

bool _within(DateTime date, DateTime start, DateTime end) =>
    !daysBetween(start, date).isNegative && !daysBetween(date, end).isNegative;
