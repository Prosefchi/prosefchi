// The Paschalion: Orthodox Pascha and the movable cycle that hangs off it.
//
// This is pure computation with no data dependency, which makes it the floor
// the app can always stand on. The GOARCH feed has a hard end date and stops;
// these functions keep working for any year.

/// The date of Orthodox Pascha in [year], as a Gregorian calendar date.
///
/// Orthodox Pascha uses the Julian computus, so this computes the Julian
/// calendar date and then converts. That conversion is why Orthodox and
/// Western Easter usually differ: as of 1900–2099 the Julian calendar runs 13
/// days behind, and the drift grows by a day roughly every century.
DateTime orthodoxPascha(int year) {
  // Meeus's Julian algorithm. Yields a date in the Julian calendar.
  final a = year % 4;
  final b = year % 7;
  final c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = (d + e + 114) ~/ 31;
  final day = (d + e + 114) % 31 + 1;

  return _gregorianFromJulianDay(_julianDayFromJulianDate(year, month, day));
}

/// A feast whose date is fixed relative to Pascha rather than to the month.
///
/// Offsets are in days from Pascha itself, so [pascha] is 0 and everything in
/// the Triodion is negative.
enum MovableFeast {
  /// Opening of the Triodion.
  publicanAndPharisee(-70),
  prodigalSon(-63),

  /// Last day meat is eaten before Great Lent.
  meatfareSunday(-56),

  /// Forgiveness Sunday; last day of dairy.
  cheesefareSunday(-49),

  /// First day of Great Lent.
  cleanMonday(-48),

  sundayOfOrthodoxy(-42),
  gregoryPalamas(-35),
  venerationOfTheCross(-28),
  johnClimacus(-21),
  maryOfEgypt(-14),
  lazarusSaturday(-8),
  palmSunday(-7),
  holyThursday(-3),
  holyFriday(-2),
  holySaturday(-1),

  pascha(0),

  /// Antipascha; the Octoechos restarts at Tone 1 here.
  thomasSunday(7),

  myrrhbearers(14),
  paralytic(21),
  midPentecost(24),
  samaritanWoman(28),
  blindMan(35),

  /// Leavetaking of Pascha, the day before Ascension.
  apodosisOfPascha(38),

  ascension(39),
  fathersOfFirstCouncil(42),
  pentecost(49),
  allSaints(56),

  /// The Apostles' Fast begins the day after All Saints and runs to 29 June,
  /// so unlike the other fasts its length varies with the date of Pascha.
  apostlesFastBegins(57);

  const MovableFeast(this.offsetFromPascha);

  /// Days from Pascha; negative before it.
  final int offsetFromPascha;

  /// The date this feast falls on in [year].
  DateTime inYear(int year) =>
      addDays(orthodoxPascha(year), offsetFromPascha);
}

/// All movable feasts in [year], earliest first.
Map<MovableFeast, DateTime> movableFeasts(int year) => {
  for (final feast in MovableFeast.values) feast: feast.inYear(year),
};

/// Adds [days] to [date] without the daylight-saving hazard of `Duration`.
///
/// `DateTime.add(Duration(days: 1))` adds 24 hours, which lands on the wrong
/// calendar day across a DST boundary. Constructing a new `DateTime` with an
/// out-of-range day normalizes correctly instead.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Days between two dates, ignoring any time component.
///
/// Compares in UTC deliberately. Subtracting two local `DateTime`s across a
/// daylight-saving change yields 23 or 25 hours for one of the days, and
/// `inDays` truncates that to one day fewer than the calendar shows.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

int _julianDayFromJulianDate(int year, int month, int day) {
  final a = (14 - month) ~/ 12;
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - 32083;
}

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
