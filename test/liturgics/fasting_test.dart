import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/liturgics/fasting.dart';
import 'package:prosefchi/liturgics/paschalion.dart';

void main() {
  group('fastSeasonFor', () {
    test('covers Great Lent from Clean Monday to Holy Saturday', () {
      for (var year = 2020; year <= 2035; year++) {
        expect(
          fastSeasonFor(MovableFeast.cleanMonday.inYear(year)),
          FastSeason.greatLent,
        );
        expect(
          fastSeasonFor(MovableFeast.holySaturday.inYear(year)),
          FastSeason.greatLent,
        );
        expect(
          fastSeasonFor(addDays(MovableFeast.cleanMonday.inYear(year), -1)),
          isNot(FastSeason.greatLent),
          reason: 'Cheesefare Sunday is not yet Lent',
        );
      }
    });

    test('covers Cheesefare week', () {
      // 2018-02-12 through 2018-02-18. Upstream calls these "Fast Day (Dairy,
      // Eggs, and Fish Allowed)", and they were the largest single group of
      // days a weekday-only rule got wrong.
      for (var day = 12; day <= 18; day++) {
        expect(
          fastSeasonFor(DateTime(2018, 2, day)),
          FastSeason.cheesefare,
          reason: '2018-02-$day',
        );
      }
    });

    test('covers the Dormition and Nativity fasts by the calendar', () {
      expect(fastSeasonFor(DateTime(2026, 8)), FastSeason.dormition);
      expect(fastSeasonFor(DateTime(2026, 8, 14)), FastSeason.dormition);
      expect(fastSeasonFor(DateTime(2026, 8, 15)), isNull, reason: 'the feast');

      expect(fastSeasonFor(DateTime(2026, 11, 15)), FastSeason.nativity);
      expect(fastSeasonFor(DateTime(2026, 12, 24)), FastSeason.nativity);
      expect(fastSeasonFor(DateTime(2026, 12, 25)), isNull);
    });

    test('ends the Apostles Fast on the eve of Peter and Paul', () {
      for (var year = 2020; year <= 2035; year++) {
        final start = MovableFeast.apostlesFastBegins.inYear(year);
        if (start.isAfter(DateTime(year, 6, 28))) continue;
        expect(fastSeasonFor(start), FastSeason.apostles);
        expect(fastSeasonFor(DateTime(year, 6, 28)), FastSeason.apostles);
        expect(fastSeasonFor(DateTime(year, 6, 29)), isNull);
      }
    });

    test('has no Apostles Fast when Pascha falls late enough', () {
      // Its start moves with Pascha while its end is fixed, so in some years
      // it vanishes rather than running backwards.
      final late = [
        for (var year = 2020; year <= 2060; year++)
          if (MovableFeast.apostlesFastBegins
              .inYear(year)
              .isAfter(DateTime(year, 6, 28)))
            year,
      ];
      expect(late, isNotEmpty, reason: 'the case should occur in range');
      for (final year in late) {
        expect(
          fastSeasonFor(DateTime(year, 6, 20)),
          isNot(FastSeason.apostles),
        );
      }
    });
  });

  group('fastFreeWeekFor', () {
    test('lifts the fast through Bright Week', () {
      final pascha = orthodoxPascha(2026);
      for (var day = 0; day < 7; day++) {
        expect(fastFreeWeekFor(addDays(pascha, day)), FastFreeWeek.bright);
      }
      expect(fastFreeWeekFor(addDays(pascha, 7)), isNull);
    });

    test('lifts it for the week after Pentecost', () {
      expect(
        fastFreeWeekFor(MovableFeast.pentecost.inYear(2026)),
        FastFreeWeek.afterPentecost,
      );
      expect(
        fastFreeWeekFor(MovableFeast.allSaints.inYear(2026)),
        FastFreeWeek.afterPentecost,
      );
    });

    test('runs from the Nativity to Theophany across the new year', () {
      expect(
        fastFreeWeekFor(DateTime(2026, 12, 25)),
        FastFreeWeek.christmastide,
      );
      expect(
        fastFreeWeekFor(DateTime(2026, 12, 31)),
        FastFreeWeek.christmastide,
      );
      expect(fastFreeWeekFor(DateTime(2026)), FastFreeWeek.christmastide);
      expect(fastFreeWeekFor(DateTime(2026, 1, 6)), FastFreeWeek.christmastide);
      expect(fastFreeWeekFor(DateTime(2026, 1, 7)), isNull);
    });
  });

  group('isFastDay', () {
    test('fasts on Wednesday and Friday in ordinary time', () {
      // Mid-October, clear of every season.
      expect(isFastDay(DateTime(2026, 10, 14)), isTrue, reason: 'Wednesday');
      expect(isFastDay(DateTime(2026, 10, 16)), isTrue, reason: 'Friday');
      expect(isFastDay(DateTime(2026, 10, 15)), isFalse, reason: 'Thursday');
      expect(isFastDay(DateTime(2026, 10, 18)), isFalse, reason: 'Sunday');
    });

    test('does not fast on the Wednesday of a fast-free week', () {
      final bright = addDays(orthodoxPascha(2026), 3);
      expect(bright.weekday, DateTime.wednesday);
      expect(isFastDay(bright), isFalse);
    });

    test('fasts on the fixed days whatever the weekday', () {
      // The Exaltation of the Cross and the Beheading of the Forerunner fast
      // even when they fall on a Sunday.
      for (final date in [DateTime(2027, 9, 14), DateTime(2026, 8, 29)]) {
        expect(isFastDay(date), isTrue, reason: '$date');
      }
    });

    test('fasts on the eve of Theophany but not on the feast', () {
      // The eve sits inside the fast-free stretch and is the exception to it.
      expect(isFastDay(DateTime(2026, 1, 5)), isTrue);
      expect(isFastDay(DateTime(2026, 1, 6)), isFalse);
      expect(isFastDay(DateTime(2021, 1, 6)), isFalse, reason: 'a Wednesday');
      expect(isFastDay(DateTime(2023, 1, 6)), isFalse, reason: 'a Friday');
    });

    test('fasts every day of Great Lent', () {
      final start = MovableFeast.cleanMonday.inYear(2026);
      for (var day = 0; day < 40; day++) {
        expect(isFastDay(addDays(start, day)), isTrue, reason: 'day $day');
      }
    });
  });
}
