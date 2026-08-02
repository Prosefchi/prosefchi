import 'prayer.dart';

/// What a reminder was reminding the reader about, so a tap can open it.
///
/// Travels as the notification's payload, written when the notification is
/// scheduled and read when it is tapped — days later, possibly by a newer
/// build. Hence a short stable string rather than an index.
sealed class ReminderTarget {
  const ReminderTarget();

  String get payload;

  /// Null where [payload] is absent or unrecognised, which is an ordinary
  /// outcome after an update. Callers treat it as "just open the app".
  static ReminderTarget? parse(String? payload) {
    if (payload == null) return null;
    if (payload == FastingTarget.slug) return const FastingTarget();
    final occasion = PrayerOccasion.bySlug(payload);
    return occasion == null ? null : PrayerTarget(occasion);
  }
}

/// A prayer rule: tapping it opens that rule to read.
final class PrayerTarget extends ReminderTarget {
  const PrayerTarget(this.occasion);

  final PrayerOccasion occasion;

  @override
  String get payload => occasion.slug;

  @override
  bool operator ==(Object other) =>
      other is PrayerTarget && other.occasion == occasion;

  @override
  int get hashCode => occasion.hashCode;
}

/// The fasting reminder: tapping it opens the day, where the rule is shown.
final class FastingTarget extends ReminderTarget {
  const FastingTarget();

  /// Distinct from every [PrayerOccasion.slug], which is what lets one payload
  /// space hold both. `test/models/reminder_test.dart` pins that.
  static const slug = 'fasting';

  @override
  String get payload => slug;

  @override
  bool operator ==(Object other) => other is FastingTarget;

  @override
  int get hashCode => slug.hashCode;
}

/// A daily reminder for one prayer occasion, separately switchable, separately
/// timed, and on its own Android channel so it can be silenced alone.
class Reminder {
  const Reminder({
    required this.occasion,
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  factory Reminder.fromJson(
    PrayerOccasion occasion,
    Map<String, dynamic> json,
  ) {
    final fallback = Reminder.defaultFor(occasion);
    return Reminder(
      occasion: occasion,
      enabled: json['enabled'] as bool? ?? fallback.enabled,
      hour: (json['hour'] as int?)?.clamp(0, 23) ?? fallback.hour,
      minute: (json['minute'] as int?)?.clamp(0, 59) ?? fallback.minute,
    );
  }

  /// Every reminder starts off, which is what makes the permission prompt
  /// arrive attached to switching one on. The times are only where it starts.
  factory Reminder.defaultFor(PrayerOccasion occasion) {
    final (hour, minute) = switch (occasion) {
      PrayerOccasion.morning => (7, 0),
      PrayerOccasion.midday => (12, 0),
      PrayerOccasion.night => (21, 0),
      PrayerOccasion.beforeCommunion => (6, 0),
      PrayerOccasion.afterCommunion => (11, 0),
    };
    return Reminder(
      occasion: occasion,
      enabled: false,
      hour: hour,
      minute: minute,
    );
  }

  final PrayerOccasion occasion;
  final bool enabled;
  final int hour;
  final int minute;

  int get notificationId => occasion.notificationId;

  String get channelId => 'prayer_${occasion.slug}';

  Reminder copyWith({bool? enabled, int? hour, int? minute}) => Reminder(
    occasion: occasion,
    enabled: enabled ?? this.enabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
  };

  /// `HH:mm`, for a caller with no BuildContext to localize through.
  String get formatted =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.occasion == occasion &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(occasion, enabled, hour, minute);

  @override
  String toString() =>
      'Reminder(${occasion.slug}, ${enabled ? "on" : "off"}, $formatted)';
}

/// A daily reminder on the days that fast.
///
/// Not a [PrayerOccasion]: it would show up in the prayers list, and unlike
/// the others it fires on some days and not others.
class FastingReminder {
  const FastingReminder({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  factory FastingReminder.fromJson(Map<String, dynamic> json) {
    const fallback = FastingReminder.initial();
    return FastingReminder(
      enabled: json['enabled'] as bool? ?? fallback.enabled,
      hour: (json['hour'] as int?)?.clamp(0, 23) ?? fallback.hour,
      minute: (json['minute'] as int?)?.clamp(0, 59) ?? fallback.minute,
    );
  }

  /// Off, like every reminder, and set for early morning: a fast is kept from
  /// waking, so a reminder that arrives after breakfast has missed its moment.
  const FastingReminder.initial() : enabled = false, hour = 6, minute = 0;

  final bool enabled;
  final int hour;
  final int minute;

  /// Well clear of the prayer reminders, which take their ids from
  /// [PrayerOccasion] and so occupy the low numbers.
  static const idBase = 1000;

  /// How many days the block covers, and so how many ids are cancelled before
  /// each refill. One number for both, or a refresh spends its platform calls
  /// cancelling ids nothing ever scheduled.
  ///
  /// 30 because iOS keeps at most 64 pending notifications per app and drops
  /// the rest silently. Through Great Lent every day fasts, so an unbounded
  /// block would crowd out the prayer reminders sharing that budget.
  static const idCapacity = 30;

  String get channelId => 'fasting';

  FastingReminder copyWith({bool? enabled, int? hour, int? minute}) =>
      FastingReminder(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
  };

  @override
  bool operator ==(Object other) =>
      other is FastingReminder &&
      other.enabled == enabled &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, hour, minute);
}
