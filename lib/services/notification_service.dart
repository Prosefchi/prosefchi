import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// What the UI needs from the scheduler. An interface because no platform
/// channel is registered under `flutter test`.
abstract interface class ReminderScheduler {
  /// Whether notifications may be posted. False if the user declined.
  Future<bool> requestPermission();

  /// Schedules [reminder] if enabled, cancels it if not.
  Future<void> apply(
    Reminder reminder, {
    required String channelName,
    required String title,
    required String body,
  });

  /// Replaces the fasting reminders with one per day in [days]. The whole
  /// block is cancelled first, so this also clears it when switched off.
  Future<void> applyFasting(
    FastingReminder reminder, {
    required List<({DateTime date, String body})> days,
    required String channelName,
    required String title,
  });

  /// Reminders tapped while the app is running. See [takeLaunchTarget] for the
  /// other half, which is the common case.
  Stream<ReminderTarget> get taps;

  /// The reminder that launched the app, or null if something else did.
  ///
  /// A tap that starts the process has nobody listening on [taps]; the platform
  /// records it against the launch intent instead. Answers once, since the
  /// platform keeps returning the same launch for the life of the process.
  Future<ReminderTarget?> takeLaunchTarget();
}

/// The scheduler used wherever one is not injected.
///
/// Shared because the initialization memo below is per-instance and guards
/// process-wide state: a second instance recopies the 1.9 MB timezone blob and
/// briefly resets the local zone to UTC. Nothing disposes it.
final sharedReminderScheduler = NotificationService();

/// Schedules the daily prayer reminders on the device. Nothing is pushed from
/// a server, so they fire with no signal and the app never learns who prays.
class NotificationService implements ReminderScheduler {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// From the flag, so a reminder is recognisably this app's even though the
  /// icon is reduced to a plain cross.
  static const _brandColour = Color(0xFFBB0602);

  /// Registers the channel now rather than leaving it to the first delivery.
  ///
  /// The plugin creates a channel when it first *posts* to one, so a reminder
  /// switched on but not yet fired appears nowhere in system settings, and the
  /// app reads as declaring no notifications at all.
  ///
  /// Safe to repeat: re-creating a channel updates its name, which is what a
  /// language change wants, and Android ignores importance changes afterwards.
  Future<void> _ensureChannel(String id, String name) async => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        AndroidNotificationChannel(
          id,
          name,
          importance: Importance.defaultImportance,
        ),
      );

  /// Stated once: the two kinds of reminder differ in how they are scheduled,
  /// not in how they look.
  NotificationDetails _detailsFor(String channelId, String channelName) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          color: _brandColour,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: channelId),
      );

  /// The future, not a bool set at the end of [_initialize]: a flag lets a
  /// second caller in while the first is still inside, and both do the work.
  Future<void>? _initialization;

  /// Reminders are wall-clock events — 7am stays 7am across a daylight saving
  /// change and when the user travels — which needs a real timezone database.
  Future<void> initialize() => _initialization ??= _initialize();

  /// Unclosed, because this lives as long as the app does.
  final _taps = StreamController<ReminderTarget>.broadcast();

  @override
  Stream<ReminderTarget> get taps => _taps.stream;

  bool _launchTargetTaken = false;

  @override
  Future<ReminderTarget?> takeLaunchTarget() async {
    if (_launchTargetTaken) return null;
    _launchTargetTaken = true;

    // Deliberately without [initialize]: one channel call answered from the
    // launch intent, where initializing would copy the timezone database
    // before the first frame on every launch.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp != true) return null;
    return ReminderTarget.parse(launch?.notificationResponse?.payload);
  }

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object catch (error) {
      // An unrecognised zone name would otherwise take the whole app down at
      // startup. UTC reminders are wrong but recoverable; a crash is not.
      debugPrint('reminders: falling back to UTC ($error)');
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        // Not the launcher icon: Android reads only the alpha channel, so
        // anything coloured arrives as a white blob. The cross alone, because
        // at 24dp the firesteels collapse into mush.
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        // Asked for when the user switches a reminder on, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      // Warm taps only; a tap that starts the process never reaches this.
      onDidReceiveNotificationResponse: (response) {
        if (ReminderTarget.parse(response.payload) case final target?) {
          _taps.add(target);
        }
      },
    );
  }

  /// False if the user declined, so the caller can leave the switch off rather
  /// than show a reminder as enabled that will never fire.
  @override
  Future<bool> requestPermission() async {
    await initialize();

    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // Only Android 13 and later prompt; earlier versions return null having
      // granted it at install time.
      return await android?.requestNotificationsPermission() ?? true;
    }

    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  /// Schedules [reminder] if it is enabled, or cancels it if not.
  ///
  /// **This does not install a standing daily alarm**, however much
  /// [DateTimeComponents.time] below reads like one. It arms tomorrow and
  /// nothing further, which is why `refreshReminders` exists.
  ///
  /// The text is baked into the scheduled notification, so callers reschedule
  /// when the language changes.
  @override
  Future<void> apply(
    Reminder reminder, {
    required String channelName,
    required String title,
    required String body,
  }) async {
    await initialize();
    await _plugin.cancel(id: reminder.notificationId);
    if (!reminder.enabled) return;

    await _ensureChannel(reminder.channelId, channelName);
    await _plugin.zonedSchedule(
      id: reminder.notificationId,
      title: title,
      body: body,
      scheduledDate: nextOccurrence(reminder.hour, reminder.minute),
      notificationDetails: _detailsFor(reminder.channelId, channelName),
      payload: PrayerTarget(reminder.occasion).payload,
      // Inexact deliberately: exact alarms need SCHEDULE_EXACT_ALARM, granted
      // by hand, or USE_EXACT_ALARM, which Play restricts to alarm apps.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Arms the *next* occurrence, not a repeating alarm. The plugin sets one
      // one-shot and its receiver arms the following one when that fires, so
      // this is a chain to be re-armed rather than a subscription.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> applyFasting(
    FastingReminder reminder, {
    required List<({DateTime date, String body})> days,
    required String channelName,
    required String title,
  }) async {
    await initialize();

    // The whole block, not the days about to be rescheduled: the last refill
    // may have covered dates this one does not, which would fire stale.
    await Future.wait([
      for (var i = 0; i < FastingReminder.idCapacity; i++)
        _plugin.cancel(id: FastingReminder.idBase + i),
    ]);
    if (!reminder.enabled) return;

    await _ensureChannel(reminder.channelId, channelName);
    final details = _detailsFor(reminder.channelId, channelName);

    for (var i = 0; i < days.length && i < FastingReminder.idCapacity; i++) {
      final day = days[i];
      final at = tz.TZDateTime(
        tz.local,
        day.date.year,
        day.date.month,
        day.date.day,
        reminder.hour,
        reminder.minute,
      );
      // Today's may already have passed by the time the app is opened.
      if (!at.isAfter(tz.TZDateTime.now(tz.local))) continue;

      await _plugin.zonedSchedule(
        id: FastingReminder.idBase + i,
        title: title,
        body: day.body,
        scheduledDate: at,
        notificationDetails: details,
        payload: const FastingTarget().payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // No matchDateTimeComponents: each fires once, on its own day.
      );
    }
  }

  /// Today at that time, or tomorrow if it has already passed. Tomorrow is the
  /// day field overflowed, never a 24 hour Duration, which lands an hour out
  /// across a daylight saving change.
  @visibleForTesting
  static tz.TZDateTime nextOccurrence(
    int hour,
    int minute, {
    tz.TZDateTime? now,
  }) {
    final from = now ?? tz.TZDateTime.now(tz.local);
    final today = tz.TZDateTime(
      from.location,
      from.year,
      from.month,
      from.day,
      hour,
      minute,
    );
    return today.isAfter(from)
        ? today
        : tz.TZDateTime(
            from.location,
            from.year,
            from.month,
            from.day + 1,
            hour,
            minute,
          );
  }
}
