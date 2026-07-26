import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location athens;

  setUpAll(() {
    tz_data.initializeTimeZones();
    athens = tz.getLocation('Europe/Athens');
  });

  group('nextOccurrence', () {
    test('is today when the time has not passed', () {
      final now = tz.TZDateTime(athens, 2026, 7, 26, 5, 30);

      expect(
        NotificationService.nextOccurrence(7, 0, now: now),
        tz.TZDateTime(athens, 2026, 7, 26, 7, 0),
      );
    });

    test('is tomorrow when the time has passed', () {
      final now = tz.TZDateTime(athens, 2026, 7, 26, 9, 0);

      expect(
        NotificationService.nextOccurrence(7, 0, now: now),
        tz.TZDateTime(athens, 2026, 7, 27, 7, 0),
      );
    });

    test('rolls over when the time is exactly now', () {
      // Otherwise a reminder scheduled at the moment it fires would be set for
      // a time already gone.
      final now = tz.TZDateTime(athens, 2026, 7, 26, 7, 0);

      expect(NotificationService.nextOccurrence(7, 0, now: now).day, 27);
    });

    test('keeps the wall-clock hour across a spring-forward', () {
      // Greece springs forward at 03:00 on the last Sunday of March, which in
      // 2026 is the 29th. Adding a 24 hour Duration from the 28th lands at
      // 08:00, an hour late. A 07:00 reminder must stay 07:00.
      final now = tz.TZDateTime(athens, 2026, 3, 28, 22, 0);
      final next = NotificationService.nextOccurrence(7, 0, now: now);

      expect(next.year, 2026);
      expect(next.month, 3);
      expect(next.day, 29);
      expect(next.hour, 7, reason: 'wall-clock time, not 24 hours later');
      expect(next.minute, 0);
    });

    test('keeps the wall-clock hour across a fall-back', () {
      // And the same in the other direction, where 24 hours would land an hour
      // early.
      final now = tz.TZDateTime(athens, 2026, 10, 24, 22, 0);
      final next = NotificationService.nextOccurrence(7, 0, now: now);

      expect(next.day, 25);
      expect(next.hour, 7);
    });

    test('crosses a month and a year boundary', () {
      expect(
        NotificationService.nextOccurrence(
          7,
          0,
          now: tz.TZDateTime(athens, 2026, 12, 31, 23, 0),
        ),
        tz.TZDateTime(athens, 2027, 1, 1, 7, 0),
      );
    });
  });
}
