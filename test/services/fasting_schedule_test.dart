import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/calendar.dart';
import 'package:prosefchi/services/fasting_schedule.dart';

/// A calendar of days keyed to what each one's fast permits.
///
/// Null is a day the source states no rule for, which is an ordinary day and
/// does not fast; [FastAllowance.free] is a day it states the fast is lifted.
/// Both answer `fasts` with false and they are not the same fact.
Calendar calendarWith(Map<String, FastAllowance?> days) => Calendar(
  language: 'en',
  source: 'https://example.test/feed.ics',
  generatedAt: DateTime(2026, 7, 26),
  start: DateTime.parse(days.keys.reduce((a, b) => a.compareTo(b) < 0 ? a : b)),
  end: DateTime.parse(days.keys.reduce((a, b) => a.compareTo(b) > 0 ? a : b)),
  days: {
    for (final entry in days.entries)
      entry.key: CalendarDay(
        date: DateTime.parse(entry.key),
        title: 'A day',
        fastAllowance: entry.value,
      ),
  },
);

void main() {
  group('fastingDaysFrom', () {
    test('takes the published ruling where the calendar reaches', () {
      // 2026-07-27 is a Monday, which the computed rules would call no fast.
      // The published calendar overrides that in both directions.
      final calendar = calendarWith({
        '2026-07-26': null,
        '2026-07-27': FastAllowance.strict,
        '2026-07-28': FastAllowance.free,
      });

      final days = fastingDaysFrom(
        DateTime(2026, 7, 26),
        calendar: calendar,
        within: 3,
        style: CalendarStyle.gregorian,
      );

      expect(days, hasLength(1));
      expect(days.single.date, DateTime(2026, 7, 27));
      expect(days.single.allowance, FastAllowance.strict);
    });

    test('carries the rule so the notification can name it', () {
      final calendar = calendarWith({'2026-07-29': FastAllowance.wineAndOil});

      final days = fastingDaysFrom(
        DateTime(2026, 7, 29),
        calendar: calendar,
        within: 1,
        style: CalendarStyle.gregorian,
      );

      expect(days.single.allowance, FastAllowance.wineAndOil);
    });

    test('computes past the end of the calendar', () {
      // The feed stops on 2026-08-31, and the Nativity Fast is well beyond it.
      final days = fastingDaysFrom(
        DateTime(2026, 11, 20),
        calendar: calendarWith({'2026-07-26': null}),
        within: 3,
        style: CalendarStyle.gregorian,
      );

      expect(days, hasLength(3), reason: 'every day of the Nativity Fast');
      expect(
        days.every((d) => d.allowance == null),
        isTrue,
        reason:
            'nothing published to quote, so the caller supplies the wording',
      );
    });

    test('works with no calendar at all', () {
      // A first launch, before anything has been fetched.
      final days = fastingDaysFrom(
        DateTime(2026, 10, 12),
        within: 7,
        style: CalendarStyle.gregorian,
      );

      expect(days.map((d) => d.date.weekday), [
        DateTime.wednesday,
        DateTime.friday,
      ]);
    });

    test('stops at the limit', () {
      // Through Great Lent every day fasts. iOS keeps only 64 pending
      // notifications for an app and drops the rest silently, so the horizon
      // has to be bounded rather than trusted to be sparse.
      final days = fastingDaysFrom(
        DateTime(2026, 2, 25),
        within: 60,
        limit: 30,
        style: CalendarStyle.gregorian,
      );

      expect(days, hasLength(30));
    });

    test('is empty when nothing in the window fasts', () {
      // Bright Week lifts the fast entirely, Wednesday and Friday included.
      final days = fastingDaysFrom(
        DateTime(2026, 4, 12),
        within: 7,
        style: CalendarStyle.gregorian,
      );

      expect(days, isEmpty);
    });

    test('starts from the given day, including it', () {
      final days = fastingDaysFrom(
        DateTime(2026, 10, 14),
        within: 1,
        style: CalendarStyle.gregorian,
      );

      expect(days.single.date, DateTime(2026, 10, 14));
    });
  });
}
