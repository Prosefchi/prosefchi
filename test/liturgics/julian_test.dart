import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/liturgics/fasting.dart';
import 'package:prosefchi/liturgics/julian.dart';
import 'package:prosefchi/liturgics/paschalion.dart';
import 'package:prosefchi/models/calendar.dart';

String key(DateTime date) => Calendar.dateKey(date);

void main() {
  group('conversion', () {
    test('the old calendar runs 13 days behind through this century', () {
      // Every one of these is why a feast is kept on the day it is.
      expect(key(julianDateOf(DateTime(2026, 1, 7))), '2025-12-25'); // Nativity
      expect(
        key(julianDateOf(DateTime(2026, 1, 19))),
        '2026-01-06',
      ); // Theophany
      expect(
        key(julianDateOf(DateTime(2026, 4, 7))),
        '2026-03-25',
      ); // Annunciation
      expect(
        key(julianDateOf(DateTime(2026, 8, 28))),
        '2026-08-15',
      ); // Dormition
      expect(
        key(julianDateOf(DateTime(2026, 9, 27))),
        '2026-09-14',
      ); // Exaltation
    });

    test('the gap is not hardcoded and widens in 2100', () {
      // 13 days from 1900-03-01 (Julian), 14 from 2100-03-01. A constant would
      // be right for every date anyone tests with and wrong afterwards.
      expect(
        daysBetween(julianDateOf(DateTime(2099, 6)), DateTime(2099, 6)),
        13,
      );
      expect(
        daysBetween(julianDateOf(DateTime(2101, 6)), DateTime(2101, 6)),
        14,
      );
    });

    test('round trips', () {
      for (var offset = 0; offset < 4000; offset += 7) {
        final date = addDays(DateTime(2020), offset);
        expect(gregorianDateOf(julianDateOf(date)), date);
      }
    });
  });

  group('fasting on the old calendar', () {
    test('the Dormition fast runs 14 to 27 August', () {
      // Julian 1 to 14 August.
      for (final (date, season) in [
        (DateTime(2026, 8, 13), null),
        (DateTime(2026, 8, 14), FastSeason.dormition),
        (DateTime(2026, 8, 27), FastSeason.dormition),
        (DateTime(2026, 8, 28), null),
      ]) {
        expect(
          fastSeasonFor(date, style: CalendarStyle.julian),
          season,
          reason: key(date),
        );
      }
    });

    test('the Nativity fast runs 28 November to 6 January', () {
      // Julian 15 November to 24 December, straddling the new year.
      for (final (date, season) in [
        (DateTime(2026, 11, 27), null),
        (DateTime(2026, 11, 28), FastSeason.nativity),
        (DateTime(2026, 12, 31), FastSeason.nativity),
        (DateTime(2027, 1, 6), FastSeason.nativity),
        (DateTime(2027, 1, 7), null),
      ]) {
        expect(
          fastSeasonFor(date, style: CalendarStyle.julian),
          season,
          reason: key(date),
        );
      }
    });

    test('Great Lent does not move, because Pascha does not', () {
      // The one thing both calendars agree on. Shifting it would put a Lenten
      // weekday on Holy Friday, which is the failure this whole design avoids.
      for (final year in [2026, 2027, 2028]) {
        final lent = MovableFeast.cleanMonday.inYear(year);
        for (final style in CalendarStyle.values) {
          expect(fastSeasonFor(lent, style: style), FastSeason.greatLent);
          expect(
            fastSeasonFor(addDays(lent, -1), style: style),
            isNot(FastSeason.greatLent),
          );
        }
        expect(
          isFastDay(orthodoxPascha(year), style: CalendarStyle.julian),
          isFalse,
          reason: 'Pascha never fasts on either calendar',
        );
      }
    });

    test('the Apostles\' Fast ends on 11 July and can no longer vanish', () {
      // Julian 28 June. On the new calendar a late Pascha can start it after
      // its own end and there is no fast that year; the extra 13 days mean the
      // old calendar always has one.
      expect(
        fastSeasonFor(DateTime(2026, 7, 11), style: CalendarStyle.julian),
        FastSeason.apostles,
      );
      expect(
        fastSeasonFor(DateTime(2026, 7, 12), style: CalendarStyle.julian),
        isNull,
      );

      for (var year = 2026; year < 2076; year++) {
        final start = MovableFeast.apostlesFastBegins.inYear(year);
        expect(
          fastSeasonFor(start, style: CalendarStyle.julian),
          FastSeason.apostles,
          reason: 'no Apostles\' Fast in $year',
        );
      }
    });

    test('Christmastide is fast free from 7 to 19 January', () {
      // Julian 25 December to 6 January, with the eve of Theophany excepted.
      expect(
        isFastDay(DateTime(2027, 1, 8), style: CalendarStyle.julian),
        isFalse,
      );
      expect(
        isFastDay(DateTime(2027, 1, 13), style: CalendarStyle.julian),
        isFalse,
        reason: 'a Wednesday inside christmastide',
      );
      expect(
        isFastDay(DateTime(2027, 1, 18), style: CalendarStyle.julian),
        isTrue,
        reason: 'the eve of Theophany is a strict fast in the middle of it',
      );
    });

    test('the fixed strict fasts move with the calendar', () {
      // The Beheading, the Exaltation, and the two eves.
      for (final date in [
        DateTime(2026, 9, 11), // Julian 29 August
        DateTime(2026, 9, 27), // Julian 14 September
        DateTime(2027, 1, 6), // Julian 25 December, the Nativity eve
      ]) {
        expect(
          isFastDay(date, style: CalendarStyle.julian),
          isTrue,
          reason: key(date),
        );
      }
    });

    test('the weekday fast is the same day on both calendars', () {
      // The calendars disagree about the date, never about the day of week.
      for (var offset = 0; offset < 365; offset++) {
        final date = addDays(DateTime(2026, 9), offset);
        if (date.weekday != DateTime.wednesday) continue;
        if (fastFreeWeekFor(date, style: CalendarStyle.julian) != null) {
          continue;
        }
        expect(
          isFastDay(date, style: CalendarStyle.julian),
          isTrue,
          reason: key(date),
        );
      }
    });
  });
}
