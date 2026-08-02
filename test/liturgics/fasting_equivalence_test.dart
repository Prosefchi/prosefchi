import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/liturgics/fasting.dart';
import 'package:prosefchi/liturgics/julian.dart';
import 'package:prosefchi/liturgics/paschalion.dart';
import 'package:prosefchi/models/calendar.dart';

/// Recomputes each answer the long way — converting per call, as the three
/// functions did before they shared one conversion — and holds the shipped
/// ones to it across 120 years of both calendars.
void main() {
  test('sharing one conversion changed no answer in 1990-2110', () {
    var checked = 0;
    for (var date = DateTime(1990); date.year < 2110; date = addDays(date, 1)) {
      for (final style in CalendarStyle.values) {
        final fixed = style == CalendarStyle.julian ? julianDateOf(date) : date;

        // The fixed-day rule, restated here against an independently derived
        // date rather than the one the implementation threads through.
        final ownFixedDay = const [
          (8, 29),
          (9, 14),
          (1, 5),
          (12, 24),
        ].contains((fixed.month, fixed.day));

        final free = fastFreeWeekFor(date, style: style);
        final season = fastSeasonFor(date, style: style);
        final expected =
            ownFixedDay ||
            (free == null &&
                (season != null ||
                    date.weekday == DateTime.wednesday ||
                    date.weekday == DateTime.friday));

        expect(
          isFastDay(date, style: style),
          expected,
          reason: '${Calendar.dateKey(date)} ${style.name}',
        );
        checked++;
      }
    }
    expect(checked, greaterThan(87000));
  });
}
