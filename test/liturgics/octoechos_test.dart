import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/liturgics/octoechos.dart';
import 'package:prosefchi/liturgics/paschalion.dart';

/// Every day of the GOARCH feed that publishes a tone or an eothinon, as
/// (date, tone, eothinon).
///
/// Taken from the same authority the app's calendar comes from, which is the
/// only ground truth available: the cycles are not derivable from anything
/// else in the feed, and 86 days out of 3287 is far too sparse to ship.
const published = <(String, int?, int?)>[
  ('2017-09-03', 4, 2),
  ('2017-09-10', 5, 3),
  ('2017-09-17', 6, 4),
  ('2017-09-24', 7, 5),
  ('2017-10-01', 8, 6),
  ('2017-10-08', 1, 7),
  ('2017-10-15', 2, 8),
  ('2017-10-22', 3, 9),
  ('2017-10-29', 4, 10),
  ('2017-11-05', 5, 11),
  ('2017-11-12', 6, 1),
  ('2017-11-19', 7, 2),
  ('2017-11-26', 8, 3),
  ('2017-12-03', 1, 4),
  ('2017-12-10', 2, 5),
  ('2017-12-17', 3, 6),
  ('2017-12-24', 4, 7),
  ('2017-12-31', 5, 8),
  ('2018-01-07', 6, 9),
  ('2018-01-14', 7, 10),
  ('2018-01-21', 8, 11),
  ('2018-01-28', 1, 1),
  ('2018-02-04', 2, 2),
  ('2018-02-11', 3, 3),
  ('2018-02-18', 4, 4),
  ('2018-02-25', 5, 5),
  ('2018-03-04', 6, 6),
  ('2018-03-11', 7, 7),
  ('2018-03-18', 8, 8),
  ('2018-03-25', 1, null),
  ('2018-06-03', 8, 1),
  ('2018-06-10', 1, 2),
  ('2018-06-17', 2, 3),
  ('2018-06-24', 3, 4),
  ('2018-07-01', 4, 5),
  ('2018-07-08', 5, 6),
  ('2018-07-15', 6, 7),
  ('2018-07-22', 7, 8),
  ('2018-07-29', 8, 9),
  ('2018-08-05', 1, 10),
  ('2018-08-12', 2, 11),
  ('2018-08-19', 3, 1),
  ('2018-08-26', 4, 2),
  ('2018-09-02', 5, 3),
  ('2018-09-09', 6, 4),
  ('2018-09-16', 7, 5),
  ('2018-09-23', 8, 6),
  ('2018-09-30', 1, 7),
  ('2018-10-07', 2, 8),
  ('2018-10-14', 3, 9),
  ('2018-10-21', 4, 10),
  ('2018-10-28', 5, 11),
  ('2018-11-04', 6, 1),
  ('2018-11-11', 7, 2),
  ('2018-11-18', 8, 3),
  ('2018-11-25', 1, 4),
  ('2018-12-02', 2, 5),
  ('2018-12-09', 3, 6),
  ('2018-12-16', 4, 7),
  ('2018-12-23', 5, 8),
  ('2018-12-30', 6, 9),
  ('2019-01-06', 7, null),
  ('2019-01-13', 8, 11),
  ('2019-01-20', 1, 1),
  ('2019-01-27', 2, 2),
  ('2019-02-03', 3, 3),
  ('2019-02-10', 4, 4),
  ('2019-02-17', 5, 5),
  ('2019-02-24', 6, 6),
  ('2019-03-03', 7, 7),
  ('2019-03-10', 8, 8),
  ('2019-03-17', 1, 9),
  ('2019-03-24', 2, 10),
  ('2019-03-31', 3, 11),
  ('2019-04-07', 4, 1),
  ('2019-04-14', 5, 2),
  ('2019-06-23', 8, 1),
  ('2019-06-30', 1, 2),
  ('2019-07-07', 2, 3),
  ('2019-07-14', 3, 4),
  ('2019-07-21', 4, 5),
  ('2019-07-28', 5, 6),
  ('2019-08-04', 6, 7),
  ('2019-08-11', 7, 8),
  ('2019-08-18', 8, 9),
  ('2019-08-25', 1, 10),
];

void main() {
  group('toneFor', () {
    test('matches every tone the feed publishes', () {
      var checked = 0;
      for (final (date, tone, _) in published) {
        if (tone == null) continue;
        expect(toneFor(DateTime.parse(date)), tone, reason: 'tone on $date');
        checked++;
      }
      expect(checked, greaterThan(80), reason: 'the table should be populated');
    });

    test('restarts at Tone 1 on Thomas Sunday', () {
      for (var year = 2018; year <= 2030; year++) {
        expect(toneFor(MovableFeast.thomasSunday.inYear(year)), 1);
      }
    });

    test('advances one tone a week and wraps after eight', () {
      final thomas = MovableFeast.thomasSunday.inYear(2026);
      expect(toneFor(addDays(thomas, 7)), 2);
      expect(toneFor(addDays(thomas, 49)), 8);
      expect(toneFor(addDays(thomas, 56)), 1, reason: 'wraps');
    });

    test('holds for the whole week, changing on the Sunday', () {
      final thomas = MovableFeast.thomasSunday.inYear(2026);
      for (var day = 0; day < 7; day++) {
        expect(toneFor(addDays(thomas, day)), 1, reason: 'day $day');
      }
      expect(toneFor(addDays(thomas, 7)), 2);
    });

    test('has no tone through Bright Week', () {
      // The Octoechos is set aside between Pascha and Thomas Sunday; each day
      // has its own proper texts, so reporting a tone would invent one.
      final pascha = orthodoxPascha(2026);
      for (var day = 0; day < 7; day++) {
        expect(toneFor(addDays(pascha, day)), isNull, reason: 'day $day');
      }
      expect(toneFor(addDays(pascha, 7)), isNotNull, reason: 'Thomas Sunday');
    });

    test('carries the previous year cycle through Great Lent', () {
      // The cycle runs continuously from one Thomas Sunday to the next Pascha.
      final beforePascha = addDays(orthodoxPascha(2026), -14);
      expect(toneFor(beforePascha), isNotNull);
    });
  });

  group('eothinonFor', () {
    test('matches every eothinon the feed publishes', () {
      var checked = 0;
      for (final (date, _, eothinon) in published) {
        if (eothinon == null) continue;
        expect(
          eothinonFor(DateTime.parse(date)),
          eothinon,
          reason: 'eothinon on $date',
        );
        checked++;
      }
      expect(checked, greaterThan(80));
    });

    test('restarts at the first on the Sunday of All Saints', () {
      for (var year = 2018; year <= 2030; year++) {
        expect(eothinonFor(MovableFeast.allSaints.inYear(year)), 1);
      }
    });

    test('wraps after eleven rather than eight', () {
      final allSaints = MovableFeast.allSaints.inYear(2026);
      expect(eothinonFor(addDays(allSaints, 70)), 11);
      expect(eothinonFor(addDays(allSaints, 77)), 1, reason: 'wraps');
    });

    test('is defined on every day of the year', () {
      // Unlike the tone it has no gap: it says where the cycle stands, not
      // that a resurrectional gospel is read that day.
      var date = DateTime(2026);
      while (date.year == 2026) {
        expect(eothinonFor(date), inInclusiveRange(1, 11));
        date = addDays(date, 1);
      }
    });
  });
}
