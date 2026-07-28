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
      // A scheduled notification is cancelled by id, so an id that shifts
      // reaches a reminder already on someone's phone and cannot address it
      // again. Written out rather than derived, so that changing one is a
      // visible edit to this list rather than a side effect of moving a line
      // in the enum.
      expect(
        {
          for (final occasion in PrayerOccasion.values)
            occasion.slug: occasion.notificationId,
        },
        {
          'morning': 0,
          'midday': 1,
          'night': 2,
          'compline': 3,
          'before_meal': 4,
          'after_meal': 5,
          'before_communion': 6,
          'after_communion': 7,
        },
      );
    });

    test('no two occasions share an id', () {
      final ids = PrayerOccasion.values.map((o) => o.notificationId).toSet();
      expect(ids, hasLength(PrayerOccasion.values.length));
    });

    test('prayer ids stay clear of the fasting block', () {
      // The fasting reminder occupies a separate range, and an overlap would
      // have one kind of reminder cancelling the other.
      for (final occasion in PrayerOccasion.values) {
        expect(occasion.notificationId, lessThan(FastingReminder.idBase));
      }
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

  group('notification payloads', () {
    // A payload is written when a notification is scheduled and read when it is
    // tapped, days later and possibly by a newer build. If it stops round
    // tripping, taps silently stop opening anything.
    test('every target survives the round trip', () {
      for (final occasion in PrayerOccasion.values) {
        final target = PrayerTarget(occasion);
        expect(ReminderTarget.parse(target.payload), target);
      }
      expect(
        ReminderTarget.parse(const FastingTarget().payload),
        const FastingTarget(),
      );
    });

    test('the fasting payload cannot be mistaken for a rule', () {
      // Both kinds share one payload space, so the fasting slug has to stay
      // clear of every occasion's.
      expect(
        PrayerOccasion.values.map((occasion) => occasion.slug),
        isNot(contains(FastingTarget.slug)),
      );
      expect(ReminderTarget.parse(FastingTarget.slug), isA<FastingTarget>());
    });

    test('an unrecognised or absent payload opens nothing', () {
      // A notification left over from a build that named things differently.
      expect(ReminderTarget.parse('vespers'), isNull);
      expect(ReminderTarget.parse(''), isNull);
      expect(ReminderTarget.parse(null), isNull);
    });
  });
}
