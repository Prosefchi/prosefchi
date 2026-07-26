import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/prayer.dart';
import '../models/reminder.dart';

/// Persists the reminder settings.
///
/// Kept behind an interface so tests can use an in-memory implementation and
/// so the storage choice is one line to change. Settings are small and
/// structured, which is what SharedPreferences is for; the calendar, being
/// hundreds of kilobytes, goes to a file instead.
abstract interface class ReminderStore {
  Future<Map<PrayerOccasion, Reminder>> readAll();
  Future<void> write(Reminder reminder);
  Future<FastingReminder> readFasting();
  Future<void> writeFasting(FastingReminder reminder);
}

/// Reads and writes through SharedPreferences, one key per occasion.
///
/// One key each rather than a single blob, so a value that fails to parse
/// costs the user that one reminder rather than all of them.
class PreferencesReminderStore implements ReminderStore {
  static String _keyFor(PrayerOccasion occasion) => 'reminder.${occasion.slug}';

  static const _fastingKey = 'reminder.fasting';

  @override
  Future<Map<PrayerOccasion, Reminder>> readAll() async {
    final preferences = await SharedPreferences.getInstance();
    return {
      for (final occasion in PrayerOccasion.values)
        occasion: _read(preferences, occasion),
    };
  }

  @override
  Future<void> write(Reminder reminder) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _keyFor(reminder.occasion),
      jsonEncode(reminder.toJson()),
    );
  }

  @override
  Future<FastingReminder> readFasting() async {
    final raw = (await SharedPreferences.getInstance()).getString(_fastingKey);
    if (raw == null) return const FastingReminder.initial();
    try {
      return FastingReminder.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      debugPrint('reminders: could not read fasting ($error)');
      return const FastingReminder.initial();
    }
  }

  @override
  Future<void> writeFasting(FastingReminder reminder) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_fastingKey, jsonEncode(reminder.toJson()));
  }

  Reminder _read(SharedPreferences preferences, PrayerOccasion occasion) {
    final raw = preferences.getString(_keyFor(occasion));
    if (raw == null) return Reminder.defaultFor(occasion);
    try {
      return Reminder.fromJson(
        occasion,
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object catch (error) {
      // Corrupt or written by a newer version. Fall back rather than losing
      // every reminder to one bad value.
      debugPrint('reminders: could not read ${occasion.slug} ($error)');
      return Reminder.defaultFor(occasion);
    }
  }
}
