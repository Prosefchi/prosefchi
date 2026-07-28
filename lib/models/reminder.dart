import 'prayer.dart';

/// What a reminder was reminding the reader about, so a tap can open it.
///
/// Travels as the notification's payload, which means it is written when the
/// notification is scheduled and read when it is tapped — possibly days later,
/// and possibly by a newer build of the app. So it is a short stable string
/// rather than an index or anything else that could shift underneath it.
sealed class ReminderTarget {
  const ReminderTarget();

  /// What to schedule the notification with.
  String get payload;

  /// The target [payload] names, or null if it is absent or unrecognised.
  ///
  /// Unrecognised is an ordinary outcome, not a bug: a notification scheduled
  /// by an earlier build can still be sitting in the shade after an update.
  /// Callers treat null as "just open the app".
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

/// A daily reminder for one prayer occasion.
///
/// Each occasion is separately switchable and separately timed, and each gets
/// its own notification channel on Android, so it can also be silenced from
/// system settings without touching the others.
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

  /// The setting an occasion starts with.
  ///
  /// Every reminder starts off. An app that begins notifying someone who never
  /// asked is presumptuous, and it would also mean requesting the notification
  /// permission before the user has any reason to say yes. The onboarding asks
  /// instead, and the times here are only what a reminder starts at once it is
  /// switched on.
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

  /// Stable per occasion, because cancelling and rescheduling has to address
  /// the same notification. Derived from the declaration order, so occasions
  /// must only ever be appended to the enum, never reordered.
  int get notificationId => occasion.index;

  /// The Android notification channel, one per occasion so each can be
  /// silenced independently from system settings.
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

  /// `HH:mm`, for a caller that wants it without a BuildContext to localize
  /// through.
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
/// Deliberately not a [PrayerOccasion]: it is not a prayer rule, it would show
/// up in the prayers list if it were one, and unlike the others it fires on
/// some days and not others.
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

  /// How many days the block covers, and so how many ids it occupies.
  ///
  /// Scheduling one notification per fasting day means a block of ids rather
  /// than one, and the whole block is cancelled before each refill so none is
  /// left behind. One number for both the scheduling and the cancelling: when
  /// this was larger than the horizon actually scheduled, every refresh spent
  /// two thirds of its platform calls cancelling ids nothing had ever used.
  ///
  /// 30 because **iOS keeps at most 64 pending notifications per app** and
  /// drops the rest without saying so. Through Great Lent every day fasts, so
  /// an unbounded block would ask for 51 at once and crowd out the eight prayer
  /// reminders sharing that budget.
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
