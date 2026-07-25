import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/liturgics/paschalion.dart';

/// Pascha dates taken from the GOARCH calendar feed itself, so the computation
/// is checked against the same authority the app's data comes from rather than
/// against a second-hand table.
const goarchPascha = <int, (int, int)>{
  2018: (4, 8),
  2019: (4, 28),
  2020: (4, 19),
  2021: (5, 2),
  2022: (4, 24),
  2023: (4, 16),
  2024: (5, 5),
  2025: (4, 20),
  2026: (4, 12),
};

/// Mid-Pentecost, also from the feed. Confirms the movable offsets are anchored
/// correctly and not merely self-consistent.
const goarchMidPentecost = <int, (int, int)>{
  2018: (5, 2),
  2019: (5, 22),
  2020: (5, 13),
  2021: (5, 26),
  2022: (5, 18),
  2023: (5, 10),
  2024: (5, 29),
  2025: (5, 14),
  2026: (5, 6),
};

/// Apodosis (leavetaking) of Pascha, from the feed.
const goarchApodosis = <int, (int, int)>{
  2018: (5, 16),
  2019: (6, 5),
  2020: (5, 27),
  2021: (6, 9),
  2022: (6, 1),
  2023: (5, 24),
  2024: (6, 12),
  2025: (5, 28),
  2026: (5, 20),
};

void main() {
  group('orthodoxPascha', () {
    test('matches the GOARCH feed for every year it covers', () {
      goarchPascha.forEach((year, expected) {
        final (month, day) = expected;
        expect(
          orthodoxPascha(year),
          DateTime(year, month, day),
          reason: 'Pascha $year',
        );
      });
    });

    test('always falls on a Sunday', () {
      for (var year = 1900; year <= 2099; year++) {
        expect(
          orthodoxPascha(year).weekday,
          DateTime.sunday,
          reason: 'Pascha $year is not a Sunday',
        );
      }
    });

    test('stays within the 4 April to 8 May Gregorian window', () {
      // The Julian computus spans 22 March to 25 April; with the 13-day offset
      // that holds through 2099 this maps to 4 April to 8 May.
      for (var year = 1900; year <= 2099; year++) {
        final pascha = orthodoxPascha(year);
        expect(
          pascha.isAfter(DateTime(year, 4, 3)) &&
              pascha.isBefore(DateTime(year, 5, 9)),
          isTrue,
          reason: 'Pascha $year fell on $pascha',
        );
      }
    });
  });

  group('MovableFeast', () {
    test('Mid-Pentecost matches the GOARCH feed', () {
      goarchMidPentecost.forEach((year, expected) {
        final (month, day) = expected;
        expect(
          MovableFeast.midPentecost.inYear(year),
          DateTime(year, month, day),
          reason: 'Mid-Pentecost $year',
        );
      });
    });

    test('Apodosis of Pascha matches the GOARCH feed', () {
      goarchApodosis.forEach((year, expected) {
        final (month, day) = expected;
        expect(
          MovableFeast.apodosisOfPascha.inYear(year),
          DateTime(year, month, day),
          reason: 'Apodosis $year',
        );
      });
    });

    test('Pascha, Palm Sunday and Pentecost fall on Sundays', () {
      for (var year = 2020; year <= 2040; year++) {
        for (final feast in [
          MovableFeast.pascha,
          MovableFeast.palmSunday,
          MovableFeast.pentecost,
          MovableFeast.thomasSunday,
          MovableFeast.allSaints,
        ]) {
          expect(
            feast.inYear(year).weekday,
            DateTime.sunday,
            reason: '${feast.name} $year',
          );
        }
      }
    });

    test('Great Lent runs 40 days from Clean Monday to Lazarus Saturday', () {
      for (var year = 2020; year <= 2040; year++) {
        expect(
          daysBetween(
            MovableFeast.cleanMonday.inYear(year),
            MovableFeast.lazarusSaturday.inYear(year),
          ),
          40,
          reason: 'Great Lent $year',
        );
      }
    });

    test('are declared in chronological order', () {
      for (var year = 2024; year <= 2030; year++) {
        final dates = movableFeasts(year).values.toList();
        for (var i = 1; i < dates.length; i++) {
          expect(
            dates[i].isAfter(dates[i - 1]),
            isTrue,
            reason: '${MovableFeast.values[i].name} $year is out of order',
          );
        }
      }
    });
  });

  group('addDays', () {
    test('crosses a spring-forward DST boundary without losing a day', () {
      // Europe/Athens springs forward on the last Sunday of March. Adding a
      // Duration of 24 hours here yields the wrong calendar day.
      expect(addDays(DateTime(2026, 3, 28), 1), DateTime(2026, 3, 29));
      expect(addDays(DateTime(2026, 3, 29), 1), DateTime(2026, 3, 30));
    });

    test('normalizes across month and year boundaries', () {
      expect(addDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(addDays(DateTime(2024, 3, 1), -1), DateTime(2024, 2, 29));
    });
  });
}
