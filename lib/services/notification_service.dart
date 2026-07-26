import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// What the UI needs from the scheduler.
///
/// An interface so screens can be tested without platform channels, which are
/// unavailable under `flutter test` and would throw on every call.
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
}

/// Schedules the daily prayer reminders on the device.
///
/// Nothing is pushed from a server. The device schedules its own reminders, so
/// they fire with no signal, cost nothing to run, need no push tokens, and the
/// app never learns when or whether anyone prays.
///
/// Each occasion gets its own Android notification channel, so a user who
/// wants the morning reminder but not the evening one can say so either here
/// or in system settings.
class NotificationService implements ReminderScheduler {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;

  /// Reminders are wall-clock events: 7am stays 7am across a daylight saving
  /// change and when the user travels. That needs a real timezone database
  /// rather than UTC offsets, which is what the timezone package provides.
  Future<void> initialize() async {
    if (_initialized) return;

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
        // TODO: replace with a monochrome silhouette in
        // android/app/src/main/res/drawable/. Android renders the notification
        // icon as a mask, so a full-colour launcher icon shows as a white
        // blob on API 21+.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permissions are requested explicitly rather than on first launch, so
        // the prompt arrives when the user switches a reminder on and knows
        // what it is for.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    _initialized = true;
  }

  /// Asks for permission to post notifications.
  ///
  /// Returns false if the user declined, so the caller can leave the switch off
  /// rather than showing a reminder as enabled that will never fire.
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
  /// The text is passed in rather than resolved here so the service stays free
  /// of localization. It is baked into the scheduled notification, so callers
  /// must reschedule when the language changes.
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

    await _plugin.zonedSchedule(
      id: reminder.notificationId,
      title: title,
      body: body,
      scheduledDate: _nextOccurrence(reminder.hour, reminder.minute),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          reminder.channelId,
          channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: reminder.channelId),
      ),
      // Inexact deliberately. Exact alarms need SCHEDULE_EXACT_ALARM, which
      // the user must grant in system settings, or USE_EXACT_ALARM, which Play
      // policy restricts to alarm and calendar apps. A reminder that may drift
      // a few minutes is a fair trade for neither of those; revisit if the
      // drift turns out to be worse in practice.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeat daily at the same wall-clock time.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel(Reminder reminder) async {
    await initialize();
    await _plugin.cancel(id: reminder.notificationId);
  }

  Future<void> cancelAll() async {
    await initialize();
    await _plugin.cancelAll();
  }

  /// Today at that time, or tomorrow if it has already passed.
  ///
  /// The next day is built by overflowing the day field rather than adding a
  /// 24 hour Duration, which lands an hour out across a daylight saving change.
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

  tz.TZDateTime _nextOccurrence(int hour, int minute) =>
      nextOccurrence(hour, minute);
}
