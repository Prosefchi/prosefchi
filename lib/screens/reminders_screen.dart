import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/occasion_labels.dart';
import '../models/calendar.dart' show CalendarStyle;
import '../models/prayer.dart';
import '../models/reminder.dart';
import '../services/calendar_repository.dart';
import '../services/fasting_schedule.dart';
import '../services/notification_service.dart';
import '../services/reminder_refresh.dart';
import '../services/reminder_store.dart';
import '../services/settings_controller.dart';
import 'occasion_ui.dart';

/// Switches each prayer reminder on or off and sets its time.
///
/// Every occasion is independent. Someone who wants only the evening reminder
/// gets only the evening reminder, and because each has its own Android
/// channel they can also silence one from system settings without losing the
/// rest.
///
/// Shrink-wraps, so it can sit on its own screen or inside a page of the
/// onboarding without either host owning a second copy of the permission flow.
class ReminderList extends StatefulWidget {
  const ReminderList({
    super.key,
    this.store,
    this.scheduler,
    this.calendars,
    this.showTimes = true,
  });

  /// Injectable so tests need neither real preferences nor platform channels.
  final ReminderStore? store;
  final ReminderScheduler? scheduler;

  /// Read when scheduling the fasting reminder, so the notification can carry
  /// the rule the Archdiocese states rather than a generic line.
  final CalendarRepository? calendars;

  /// Whether to offer the time picker.
  ///
  /// Off during onboarding, where the only question is which prayers to be
  /// reminded of. The times are there to adjust afterwards.
  final bool showTimes;

  @override
  State<ReminderList> createState() => _ReminderListState();
}

class _ReminderListState extends State<ReminderList> {
  late final ReminderStore _store = widget.store ?? PreferencesReminderStore();
  late final ReminderScheduler _scheduler =
      widget.scheduler ?? sharedReminderScheduler;
  late final CalendarRepository _calendars =
      widget.calendars ?? sharedCalendarRepository;

  Map<PrayerOccasion, Reminder> _reminders = {};
  FastingReminder _fasting = const FastingReminder.initial();
  bool _loading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Independent reads over the same preferences; no reason to serialize.
    final (reminders, fasting) = await (
      _store.readAll(),
      _store.readFasting(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _reminders = reminders;
      _fasting = fasting;
      _loading = false;
    });
  }

  /// Unlike a prayer reminder this is not one repeating alarm but a block of
  /// one-offs, so switching it on schedules a horizon of them and switching it
  /// off clears the whole block.
  Future<void> _updateFasting(FastingReminder reminder) async {
    final l10n = AppLocalizations.of(context);
    final language = languageFor(Localizations.localeOf(context));
    final style =
        SettingsScope.maybeOf(context)?.calendarStyle ??
        CalendarStyle.gregorian;

    if (reminder.enabled && !_fasting.enabled && !await _ensurePermission()) {
      return;
    }
    if (!mounted) return;

    setState(() => _fasting = reminder);

    await _store.writeFasting(reminder);
    await refreshFastingReminders(
      reminder: reminder,
      calendars: _calendars,
      scheduler: _scheduler,
      language: language,
      style: style,
      l10n: l10n,
    );
  }

  /// Requests notification permission, reporting whether it was granted.
  ///
  /// Called on the first switch-on rather than at launch, so the prompt arrives
  /// attached to an action whose purpose is obvious. Every reminder ships off
  /// precisely so that this is the flow.
  Future<bool> _ensurePermission() async {
    final granted = await _scheduler.requestPermission();
    if (!mounted) return false;
    setState(() => _permissionDenied = !granted);
    return granted;
  }

  /// Shows the picker seeded from an hour and minute the caller holds.
  Future<TimeOfDay?> _askTime(int hour, int minute) => showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: hour, minute: minute),
  );

  /// The trailing time button, or nothing when times are not on offer.
  Widget? _timeButton(VoidCallback onPressed) => widget.showTimes
      ? IconButton(
          icon: const Icon(Icons.schedule),
          tooltip: MaterialLocalizations.of(context).timePickerInputHelpText,
          onPressed: onPressed,
        )
      : null;

  Future<void> _pickFastingTime() async {
    if (await _askTime(_fasting.hour, _fasting.minute) case final time?) {
      await _updateFasting(
        _fasting.copyWith(hour: time.hour, minute: time.minute),
      );
    }
  }

  /// Persists first, then schedules.
  ///
  /// If scheduling fails the setting is still what the user chose, and the next
  /// launch re-applies it. Scheduling first would risk a live notification with
  /// nothing on disk to explain it.
  Future<void> _update(Reminder reminder) async {
    final l10n = AppLocalizations.of(context);

    if (reminder.enabled &&
        !_reminders[reminder.occasion]!.enabled &&
        !await _ensurePermission()) {
      return;
    }
    if (!mounted) return;

    setState(() => _reminders = {..._reminders, reminder.occasion: reminder});

    await _store.write(reminder);
    // Through the shared helper, so the wording here and the wording the daily
    // refresh reschedules with cannot drift apart.
    await applyPrayerReminder(_scheduler, reminder, l10n);
  }

  Future<void> _pickTime(Reminder reminder) async {
    if (await _askTime(reminder.hour, reminder.minute) case final time?) {
      await _update(reminder.copyWith(hour: time.hour, minute: time.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_permissionDenied)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.reminderPermissionDenied,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        for (final occasion in PrayerOccasion.values) ...[
          // A heading at each change of group. The enum is ordered so every
          // group is contiguous, so this is a comparison with the previous
          // entry rather than a separate grouping pass.
          if (occasion.startsGroup)
            GroupHeading(
              occasion: occasion,
              label: l10n.groupLabel(occasion.group),
            ),
          if (_reminders[occasion] case final reminder?)
            SwitchListTile(
              value: reminder.enabled,
              onChanged: (enabled) =>
                  _update(reminder.copyWith(enabled: enabled)),
              title: Text(l10n.occasionLabel(occasion)),
              subtitle: widget.showTimes
                  ? Text(
                      reminder.enabled
                          ? _formatTime(context, reminder.hour, reminder.minute)
                          : l10n.reminderOff,
                    )
                  : null,
              secondary: _timeButton(() => _pickTime(reminder)),
            ),
        ],
        // Set apart because it is a different kind of reminder: it fires on
        // some days and not others, where every rule above fires daily.
        const Divider(height: 24),
        SwitchListTile(
          value: _fasting.enabled,
          onChanged: (enabled) =>
              _updateFasting(_fasting.copyWith(enabled: enabled)),
          title: Text(l10n.fastingReminder),
          subtitle: Text(
            _fasting.enabled && widget.showTimes
                ? '${_formatTime(context, _fasting.hour, _fasting.minute)}'
                      ' · ${l10n.fastingReminderSubtitle}'
                : l10n.fastingReminderSubtitle,
          ),
          secondary: _timeButton(_pickFastingTime),
        ),
      ],
    );
  }

  /// Uses the locale's own clock convention rather than forcing 24 hour.
  static String _formatTime(BuildContext context, int hour, int minute) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: hour, minute: minute),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
}

/// The reminder list on a screen of its own.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({
    super.key,
    this.store,
    this.scheduler,
    this.calendars,
  });

  final ReminderStore? store;
  final ReminderScheduler? scheduler;
  final CalendarRepository? calendars;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).reminders)),
    body: ListView(
      children: [
        ReminderList(store: store, scheduler: scheduler, calendars: calendars),
      ],
    ),
  );
}
