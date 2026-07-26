import 'dart:async';

import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/reminder.dart';
import 'package:prosefchi/services/notification_service.dart';
import 'package:prosefchi/services/reminder_store.dart';

/// An in-memory [ReminderStore] for tests.
///
/// Widget tests run inside a `FakeAsync` zone, where the real store's
/// SharedPreferences platform channel is not registered at all.
class MemoryReminderStore implements ReminderStore {
  MemoryReminderStore([Map<PrayerOccasion, Reminder>? initial])
    : _reminders = {
        for (final occasion in PrayerOccasion.values)
          occasion: initial?[occasion] ?? Reminder.defaultFor(occasion),
      };

  final Map<PrayerOccasion, Reminder> _reminders;

  /// Every write in order, for tests that care that something was persisted and
  /// not merely held in widget state.
  final List<Reminder> written = [];

  FastingReminder fasting = const FastingReminder.initial();

  @override
  Future<Map<PrayerOccasion, Reminder>> readAll() async => {..._reminders};

  @override
  Future<void> write(Reminder reminder) async {
    _reminders[reminder.occasion] = reminder;
    written.add(reminder);
  }

  @override
  Future<FastingReminder> readFasting() async => fasting;

  @override
  Future<void> writeFasting(FastingReminder reminder) async =>
      fasting = reminder;
}

/// A [ReminderScheduler] that records instead of scheduling.
///
/// The real one reaches a platform channel on every call, and none is
/// registered under `flutter test`.
class RecordingScheduler implements ReminderScheduler {
  RecordingScheduler({this.granted = true});

  /// What [requestPermission] answers, so a test can drive the declined path.
  final bool granted;

  int permissionRequests = 0;
  final List<Reminder> applied = [];
  final List<String> titles = [];

  /// What the app was launched by, for tests of the tap route. Cleared on the
  /// first read, like the real one.
  ReminderTarget? launchTarget;

  final _taps = StreamController<ReminderTarget>.broadcast();

  @override
  Stream<ReminderTarget> get taps => _taps.stream;

  @override
  Future<ReminderTarget?> takeLaunchTarget() async {
    final target = launchTarget;
    launchTarget = null;
    return target;
  }

  /// Stands in for the reader tapping a notification while the app is open.
  void tap(ReminderTarget target) => _taps.add(target);

  /// The days most recently scheduled, or empty when the block was cleared.
  List<({DateTime date, String body})> fastingDays = const [];

  /// Counts calls rather than only keeping the last, so a test can tell "left
  /// alone" from "rescheduled with the same days".
  int fastingApplies = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return granted;
  }

  @override
  Future<void> apply(
    Reminder reminder, {
    required String channelName,
    required String title,
    required String body,
  }) async {
    applied.add(reminder);
    titles.add(title);
  }

  @override
  Future<void> applyFasting(
    FastingReminder reminder, {
    required List<({DateTime date, String body})> days,
    required String channelName,
    required String title,
  }) async {
    fastingApplies++;
    fastingDays = reminder.enabled ? days : const [];
  }
}
