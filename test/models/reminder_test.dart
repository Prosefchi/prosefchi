import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/reminder.dart';

void main() {
  group('defaults', () {
    test('every reminder starts off', () {
      // Notifying someone who never asked is presumptuous, and it would mean
      // requesting the notification permission before they have any reason to
      // say yes. The welcome flow asks instead.
      expect(
        PrayerOccasion.values.map(Reminder.defaultFor).where((r) => r.enabled),
        isEmpty,
      );
    });

    test('every occasion has a usable default time', () {
      for (final occasion in PrayerOccasion.values) {
        final reminder = Reminder.defaultFor(occasion);
        expect(reminder.hour, inInclusiveRange(0, 23));
        expect(reminder.minute, inInclusiveRange(0, 59));
      }
    });
  });

  group('grouping', () {
    test('each group is contiguous in declaration order', () {
      // The reminders list emits a heading whenever the group changes from the
      // previous entry, so a group split across the list would render twice.
      final seen = <PrayerGroup>{};
      PrayerGroup? previous;
      for (final occasion in PrayerOccasion.values) {
        if (occasion.group != previous) {
          expect(
            seen.add(occasion.group),
            isTrue,
            reason: '${occasion.group} appears in more than one run',
          );
          previous = occasion.group;
        }
      }
    });

    test('Communion is liturgical, the rest daily', () {
      expect(PrayerOccasion.beforeCommunion.group, PrayerGroup.liturgy);
      expect(PrayerOccasion.afterCommunion.group, PrayerGroup.liturgy);
      expect(PrayerOccasion.morning.group, PrayerGroup.daily);
      expect(PrayerOccasion.beforeMeal.group, PrayerGroup.daily);
    });
  });

  group('identity', () {
    test('notification ids are unique across occasions', () {
      final ids = PrayerOccasion.values
          .map((o) => Reminder.defaultFor(o).notificationId)
          .toSet();

      expect(ids, hasLength(PrayerOccasion.values.length));
    });

    test('channel ids are unique and namespaced', () {
      final channels = PrayerOccasion.values
          .map((o) => Reminder.defaultFor(o).channelId)
          .toSet();

      expect(channels, hasLength(PrayerOccasion.values.length));
      expect(channels, everyElement(startsWith('prayer_')));
    });

    test('the id of an existing occasion never moves', () {
      // Ids come from declaration order, and a scheduled notification is
      // cancelled by id. Reordering the enum would orphan live reminders on
      // devices, so occasions may only ever be appended.
      expect(Reminder.defaultFor(PrayerOccasion.morning).notificationId, 0);
      expect(Reminder.defaultFor(PrayerOccasion.midday).notificationId, 1);
      expect(Reminder.defaultFor(PrayerOccasion.night).notificationId, 2);
      expect(Reminder.defaultFor(PrayerOccasion.compline).notificationId, 3);
    });
  });

  group('json', () {
    test('round-trips', () {
      const reminder = Reminder(
        occasion: PrayerOccasion.morning,
        enabled: true,
        hour: 6,
        minute: 30,
      );

      expect(
        Reminder.fromJson(PrayerOccasion.morning, reminder.toJson()),
        reminder,
      );
    });

    test('falls back to the default for a missing field', () {
      final reminder = Reminder.fromJson(PrayerOccasion.night, {'hour': 22});
      final fallback = Reminder.defaultFor(PrayerOccasion.night);

      expect(reminder.hour, 22);
      expect(reminder.enabled, fallback.enabled);
      expect(reminder.minute, fallback.minute);
    });

    test('clamps an out-of-range time rather than scheduling nonsense', () {
      final reminder = Reminder.fromJson(PrayerOccasion.morning, {
        'hour': 99,
        'minute': -5,
      });

      expect(reminder.hour, 23);
      expect(reminder.minute, 0);
    });
  });

  test('copyWith changes only what it is given', () {
    final original = Reminder.defaultFor(PrayerOccasion.morning);
    final changed = original.copyWith(hour: 5);

    expect(changed.hour, 5);
    expect(changed.minute, original.minute);
    expect(changed.enabled, original.enabled);
    expect(changed.occasion, original.occasion);
  });

  test('formats as zero-padded HH:mm', () {
    expect(
      const Reminder(
        occasion: PrayerOccasion.morning,
        enabled: true,
        hour: 6,
        minute: 5,
      ).formatted,
      '06:05',
    );
  });
}
