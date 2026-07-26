import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../l10n/occasion_labels.dart';
import '../models/reminder.dart';
import 'calendar_repository.dart';
import 'fasting_schedule.dart';
import 'notification_service.dart';
import 'reminder_store.dart';
import 'settings_controller.dart';

/// Schedules one prayer reminder with the text for its occasion.
///
/// The one place that decides what a prayer notification is called and says.
/// Both the reminders screen, applying what the user just chose, and
/// [refreshReminders], re-arming everything, go through here — otherwise the
/// screen's wording and the refresh's could drift, and the drift would be
/// invisible, since the next refresh silently replaces whatever the screen set.
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
/// Both kinds need this, for the same underlying reason: **neither is a
/// standing alarm**, however much the prayer reminders look like one.
///
/// A prayer reminder is scheduled with `matchDateTimeComponents` and then never
/// touched again, which reads as "set once, repeats forever". The plugin does
/// not implement it that way. It arms a *single* one-shot `AlarmManager` alarm,
/// and when that fires `ScheduledNotificationReceiver` shows the notification
/// and arms the next one. Tomorrow exists only because today fired: it is a
/// chain, not a repetition. Break one link and it never resumes.
///
/// Links break without a reboot, so the boot receiver in the manifest does not
/// cover it: a force stop, an OEM task killer on swipe-away, "Restricted"
/// battery use, or the receiver itself failing. Android may also defer an
/// inexact `setAndAllowWhileIdle` alarm for hours when the app sits in a low
/// standby bucket, which shows up as a reminder that arrives late.
///
/// The fasting block decays more simply — it is a bounded horizon that runs out.
///
/// Idempotent, so it can be called whenever the app is opened without checking
/// whether anything changed. Not free, though: with everything enabled it is
/// the eight prayer reminders plus a whole fasting block cancelled and rebuilt,
/// on the order of seventy platform calls. [ReminderRefresher] is what keeps
/// that to once a day.
Future<void> refreshReminders({
  required ReminderStore store,
  required CalendarRepository calendars,
  required ReminderScheduler scheduler,
  required String language,
  required AppLocalizations l10n,
}) async {
  // Independent reads over the same preferences; no reason to serialize.
  final (reminders, fasting) = await (
    store.readAll(),
    store.readFasting(),
  ).wait;

  // Only the enabled ones, so that the common path — every reminder ships off —
  // neither wakes the notification plugin nor initializes the timezone
  // database. Switching a reminder off already cancels it, so there is nothing
  // here for the rest to repair.
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
  );
}

/// Keeps the device's reminder schedule alive for as long as the app runs.
///
/// Owned by `main` rather than by a screen. Nothing about re-arming is a
/// navigation concern, and hanging it off a widget makes its coverage depend on
/// which widget is mounted: the app opens on the welcome flow until that is
/// completed, and the welcome flow can switch a reminder on, so a reminder
/// enabled there and left there would never be re-armed at all.
///
/// Needs no [BuildContext]. The language comes from [SettingsController], which
/// resolves it outside the tree for exactly this purpose, and the strings from
/// the delegate directly.
class ReminderRefresher {
  ReminderRefresher({
    required this.settings,
    ReminderStore? store,
    ReminderScheduler? scheduler,
    CalendarRepository? calendars,
  }) : _store = store ?? PreferencesReminderStore(),
       _scheduler = scheduler ?? sharedReminderScheduler,
       _calendars = calendars ?? sharedCalendarRepository;

  /// Read for the language at each refresh rather than captured once, so a
  /// switch between refreshes is picked up.
  final SettingsController settings;

  final ReminderStore _store;
  final ReminderScheduler _scheduler;
  final CalendarRepository _calendars;

  AppLifecycleListener? _listener;

  /// The day the schedule was last rebuilt, and only ever a day on which it
  /// succeeded — a failed attempt leaves this alone so the next resume retries
  /// rather than writing the day off.
  DateTime? _refreshedOn;

  /// Guards re-entry, which stamping only on success would otherwise allow:
  /// Android delivers a `resumed` shortly after launch, and that would arrive
  /// while the launch refresh was still in flight.
  bool _refreshing = false;

  /// Starts refreshing on launch and whenever the app is brought back.
  ///
  /// Resuming counts because a phone that is never restarted keeps a process
  /// alive for weeks, and once per launch would then not run again in all that
  /// time — which is the stretch over which a schedule decays.
  void start() {
    _listener ??= AppLifecycleListener(onResume: refresh);
    refresh();
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }

  /// Rebuilds the schedule, at most once per calendar day.
  ///
  /// The day is the right granularity on both sides: it is when the fasting
  /// horizon moves on and when a missed prayer reminder would first be noticed,
  /// and it keeps a glance at another app from rebuilding the whole block.
  Future<void> refresh() async {
    final now = DateTime.now();
    // Day precision by construction rather than by subtracting a Duration,
    // which lands an hour out across a daylight saving change.
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
