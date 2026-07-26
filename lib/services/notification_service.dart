import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Color;

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

  /// Replaces the fasting reminders with one per day in [days].
  ///
  /// The whole block is cancelled first, so this both refills the schedule and
  /// clears it when the reminder is switched off.
  Future<void> applyFasting(
    FastingReminder reminder, {
    required List<({DateTime date, String body})> days,
    required String channelName,
    required String title,
  });

  /// Reminders tapped while the app is running.
  ///
  /// A broadcast stream, and it only carries taps the plugin can report — see
  /// [takeLaunchTarget] for the other half, which is the common case.
  Stream<ReminderTarget> get taps;

  /// The reminder that launched the app, or null if something else did.
  ///
  /// Separate from [taps] because a tap that starts the process has nobody
  /// listening yet: the platform records it against the launch intent instead,
  /// and this reads it back. Answers once — the platform keeps returning the
  /// same launch for the life of the process, so a second caller would send the
  /// reader somewhere they did not ask to go a second time.
  Future<ReminderTarget?> takeLaunchTarget();
}

/// The scheduler used wherever one is not injected.
///
/// Shared for the same reason as [sharedCalendarRepository]: the initialization
/// memo below is per-instance, and it guards process-wide state. A screen
/// building its own would copy a 1.9 MB timezone blob and rebuild every
/// location again, and would briefly leave the local zone set back to UTC while
/// it did. Lives as long as the app, so nothing disposes it.
final sharedReminderScheduler = NotificationService();

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

  /// Taken from the flag, so a reminder is recognisably from this app even
  /// though the icon itself is reduced to a plain cross.
  static const _brandColour = Color(0xFFBB0602);

  /// Registers the channel now rather than leaving it to the first delivery.
  ///
  /// The plugin creates a channel when it first *posts* to one, so without this
  /// a reminder that is switched on but has not fired yet appears nowhere in the
  /// system notification settings — the app looks as though it declares no
  /// notifications at all. It also means the per-rule control this app promises
  /// is not actually there until each rule has fired once.
  ///
  /// Safe to repeat: re-creating an existing channel updates its name, which is
  /// what a language change wants, and Android deliberately ignores importance
  /// changes afterwards so it cannot undo the user's own choices. Resolves to
  /// null off Android, where channels do not exist.
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

  /// How every notification this app posts is presented. Stated once: the two
  /// kinds differ in how they are scheduled, not in how they look.
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

  /// The initialization itself, not a flag that it happened. A bool set at the
  /// end of [_initialize] would let a second caller in while the first was
  /// still inside it, and both would do the work. Holding the future means the
  /// second caller waits on the first one's.
  Future<void>? _initialization;

  /// Reminders are wall-clock events: 7am stays 7am across a daylight saving
  /// change and when the user travels. That needs a real timezone database
  /// rather than UTC offsets, which is what the timezone package provides.
  Future<void> initialize() => _initialization ??= _initialize();

  /// Broadcast, because both the shell and a test may want to watch, and
  /// unclosed, because this lives as long as the app does.
  final _taps = StreamController<ReminderTarget>.broadcast();

  @override
  Stream<ReminderTarget> get taps => _taps.stream;

  bool _launchTargetTaken = false;

  @override
  Future<ReminderTarget?> takeLaunchTarget() async {
    if (_launchTargetTaken) return null;
    _launchTargetTaken = true;

    // Deliberately without [initialize]. This is a single channel call the
    // platform answers from the launch intent, so asking costs nothing on the
    // ordinary launch, where copying the timezone database would be the most
    // expensive thing the app did before its first frame.
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
        // A white-on-transparent silhouette, not the launcher icon. Android
        // reads only the alpha channel of a notification icon, so anything
        // with colour in it arrives as a featureless white blob.
        //
        // The cross alone rather than the full emblem: at the 24dp the status
        // bar renders these at, the firesteels collapse into grey mush that
        // reads as a rendering fault.
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        // Permissions are requested explicitly rather than on first launch, so
        // the prompt arrives when the user switches a reminder on and knows
        // what it is for.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      // Taps arriving while the app is already running. A tap that starts the
      // process is not reported here; `takeLaunchTarget` covers that.
      onDidReceiveNotificationResponse: (response) {
        if (ReminderTarget.parse(response.payload) case final target?) {
          _taps.add(target);
        }
      },
    );
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
  /// **This does not install a standing daily alarm**, however much
  /// [DateTimeComponents.time] below reads like one. It arms tomorrow and
  /// nothing further; see `refreshReminders`, which exists because of that and
  /// has to be called for these to keep firing.
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

    await _ensureChannel(reminder.channelId, channelName);
    await _plugin.zonedSchedule(
      id: reminder.notificationId,
      title: title,
      body: body,
      scheduledDate: nextOccurrence(reminder.hour, reminder.minute),
      notificationDetails: _detailsFor(reminder.channelId, channelName),
      // So a tap can open the rule this is reminding them of.
      payload: PrayerTarget(reminder.occasion).payload,
      // Inexact deliberately. Exact alarms need SCHEDULE_EXACT_ALARM, which
      // the user must grant in system settings, or USE_EXACT_ALARM, which Play
      // policy restricts to alarm and calendar apps. A reminder that may drift
      // a few minutes is a fair trade for neither of those; revisit if the
      // drift turns out to be worse in practice.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Arms the *next* occurrence at this wall-clock time, not a repeating
      // alarm: the plugin schedules one one-shot and its broadcast receiver
      // arms the following one when that fires. So this is a chain that has to
      // be re-armed, not a subscription that keeps itself going.
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

    // Clear the whole block rather than the days about to be rescheduled: the
    // previous refill may have covered dates this one does not, and those
    // would otherwise fire with stale text.
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
        // Deliberately no matchDateTimeComponents: each of these fires once,
        // on its own day, and is replaced at the next refill.
      );
    }
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
}
