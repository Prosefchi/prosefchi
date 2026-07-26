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
      PrayerOccasion.compline => (22, 0),
      PrayerOccasion.beforeMeal => (13, 0),
      PrayerOccasion.afterMeal => (13, 30),
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
