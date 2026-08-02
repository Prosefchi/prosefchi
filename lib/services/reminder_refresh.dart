import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../l10n/occasion_labels.dart';
import '../models/calendar.dart' show CalendarStyle;
import '../models/reminder.dart';
import 'calendar_repository.dart';
import 'fasting_schedule.dart';
import 'notification_service.dart';
import 'reminder_store.dart';
import 'settings_controller.dart';

/// The one place that names a prayer notification's channel, title and body.
/// Two copies would drift silently, because the daily refresh overwrites
/// whatever the reminders screen scheduled.
Future<void> applyPrayerReminder(
  ReminderScheduler scheduler,
  Reminder reminder,
  AppLocalizations l10n,
) {
  final label = l10n.occasionLabel(reminder.occasion);
  return scheduler.apply(
    reminder,
    channelName: label,
    title: label,
    body: l10n.reminderBody,
  );
}

/// Re-arms every enabled reminder from what is stored.
///
/// **Neither kind is a standing alarm.** A prayer reminder is a chain of
/// one-shots — the receiver arms tomorrow when today fires — so one broken
/// link never resumes, and most ways it breaks involve no reboot. The fasting
/// block decays more simply: it is a bounded horizon that runs out.
///
/// Idempotent, and not free: with everything enabled it is on the order of
/// seventy platform calls, which is what [ReminderRefresher] throttles.
Future<void> refreshReminders({
  required ReminderStore store,
  required CalendarRepository calendars,
  required ReminderScheduler scheduler,
  required String language,
  required AppLocalizations l10n,
  required CalendarStyle style,
}) async {
  // Independent reads over the same preferences; no reason to serialize.
  final (reminders, fasting) = await (
    store.readAll(),
    store.readFasting(),
  ).wait;

  // Only the enabled ones, so the common path — every reminder ships off —
  // never wakes the plugin. Switching one off already cancelled it.
  for (final reminder in reminders.values) {
    if (!reminder.enabled) continue;
    await applyPrayerReminder(scheduler, reminder, l10n);
  }

  if (!fasting.enabled) return;

  await refreshFastingReminders(
    reminder: fasting,
    calendars: calendars,
    scheduler: scheduler,
    language: language,
    l10n: l10n,
    style: style,
  );
}

/// Re-arms everything a change of language or calendar invalidates.
///
/// A notification's text and its date are both fixed when it is scheduled, so
/// one already pending carries the old language and the old calendar's fast
/// days until something rebuilds it, and [ReminderRefresher] is throttled to
/// once a calendar day and will not. Every screen that offers either setting
/// calls this; one that did not would put that bug back on its own.
///
/// Call it after the setting is written, since it reads both back from
/// [settings].
Future<void> rescheduleReminders(
  SettingsController settings, {
  ReminderStore? store,
  CalendarRepository? calendars,
  ReminderScheduler? scheduler,
}) async {
  final language = settings.effectiveLanguage;
  await refreshReminders(
    store: store ?? PreferencesReminderStore(),
    calendars: calendars ?? sharedCalendarRepository,
    scheduler: scheduler ?? sharedReminderScheduler,
    language: language,
    style: settings.calendarStyle,
    l10n: await AppLocalizations.delegate.load(Locale(language)),
  );
}

/// Keeps the device's reminder schedule alive for as long as the app runs.
///
/// Owned by `main` rather than by a screen: hung off a widget, its coverage is
/// whatever navigation reaches, and the welcome flow can switch a reminder on
/// before any shell mounts. Needs no [BuildContext].
class ReminderRefresher {
  ReminderRefresher({
    required this.settings,
    ReminderStore? store,
    ReminderScheduler? scheduler,
    CalendarRepository? calendars,
  }) : _store = store ?? PreferencesReminderStore(),
       _scheduler = scheduler ?? sharedReminderScheduler,
       _calendars = calendars ?? sharedCalendarRepository;

  /// Read at each refresh rather than captured once, so a language switch
  /// between refreshes is picked up.
  final SettingsController settings;

  final ReminderStore _store;
  final ReminderScheduler _scheduler;
  final CalendarRepository _calendars;

  AppLifecycleListener? _listener;

  /// Stamped only on a day the rebuild succeeded, so a failure retries on the
  /// next resume rather than writing the day off.
  DateTime? _refreshedOn;

  /// Guards re-entry, which stamping only on success allows: Android delivers
  /// a `resumed` shortly after launch, while that refresh is still in flight.
  bool _refreshing = false;

  /// Resuming counts, not only launching: a phone that is never restarted
  /// keeps a process alive for weeks, which is the stretch a schedule decays
  /// over.
  void start() {
    _listener ??= AppLifecycleListener(onResume: refresh);
    refresh();
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }

  /// Rebuilds the schedule, at most once per calendar day: that is when the
  /// fasting horizon moves and when a missed reminder is first noticed.
  Future<void> refresh() async {
    final now = DateTime.now();
    // By construction, never by subtracting a Duration, which lands an hour
    // out across a daylight saving change.
    final today = DateTime(now.year, now.month, now.day);
    if (_refreshedOn == today || _refreshing) return;

    _refreshing = true;
    try {
      final language = settings.effectiveLanguage;
      await refreshReminders(
        store: _store,
        calendars: _calendars,
        scheduler: _scheduler,
        language: language,
        l10n: await AppLocalizations.delegate.load(Locale(language)),
        style: settings.calendarStyle,
      );
      _refreshedOn = today;
    } on Object catch (error) {
      // Nothing the user can act on, and the reminders already scheduled are
      // untouched. Leaving the day unstamped is the retry.
      debugPrint('reminders: refresh failed ($error)');
    } finally {
      _refreshing = false;
    }
  }
}
