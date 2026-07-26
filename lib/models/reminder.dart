import 'prayer.dart';

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
  /// Only the rules tied to a time of day are on by default. Meals and
  /// Communion are occasions rather than hours: a daily alarm to say the
  /// preparation prayers is wrong for someone who receives monthly, so they
  /// start off and carry a nominal time for whoever wants them.
  factory Reminder.defaultFor(PrayerOccasion occasion) => switch (occasion) {
    PrayerOccasion.morning => Reminder(
      occasion: occasion,
      enabled: true,
      hour: 7,
      minute: 0,
    ),
    PrayerOccasion.midday => Reminder(
      occasion: occasion,
      enabled: false,
      hour: 12,
      minute: 0,
    ),
    PrayerOccasion.night => Reminder(
      occasion: occasion,
      enabled: true,
      hour: 21,
      minute: 0,
    ),
    PrayerOccasion.compline => Reminder(
      occasion: occasion,
      enabled: false,
      hour: 22,
      minute: 0,
    ),
    PrayerOccasion.beforeMeal => Reminder(
      occasion: occasion,
      enabled: false,
      hour: 13,
      minute: 0,
    ),
    PrayerOccasion.afterMeal => Reminder(
      occasion: occasion,
      enabled: false,
      hour: 13,
      minute: 30,
    ),
    PrayerOccasion.beforeCommunion => Reminder(
      occasion: occasion,
      enabled: false,
      hour: 6,
      minute: 0,
    ),
    PrayerOccasion.afterCommunion => Reminder(
      occasion: occasion,
      enabled: false,
      hour: 11,
      minute: 0,
    ),
  };

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
