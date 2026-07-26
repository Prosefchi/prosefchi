import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/occasion_labels.dart';
import '../models/prayer.dart';
import '../models/reminder.dart';
import '../services/calendar_repository.dart';
import '../services/fasting_schedule.dart';
import '../services/notification_service.dart';
import '../services/reminder_store.dart';
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
      widget.scheduler ?? NotificationService();
  late final CalendarRepository _calendars =
      widget.calendars ?? CalendarRepository();

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
    final reminders = await _store.readAll();
    final fasting = await _store.readFasting();
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
    final language = _languageFor(Localizations.localeOf(context));

    if (reminder.enabled && !_fasting.enabled) {
      final granted = await _scheduler.requestPermission();
      if (!mounted) return;
      if (!granted) {
        setState(() => _permissionDenied = true);
        return;
      }
      setState(() => _permissionDenied = false);
    }

    setState(() => _fasting = reminder);

    await _store.writeFasting(reminder);
    await refreshFastingReminders(
      reminder: reminder,
      calendars: _calendars,
      scheduler: _scheduler,
      language: language,
      l10n: l10n,
    );
  }

  Future<void> _pickFastingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _fasting.hour, minute: _fasting.minute),
    );
    if (picked == null) return;
    await _updateFasting(
      _fasting.copyWith(hour: picked.hour, minute: picked.minute),
    );
  }

  static String _languageFor(Locale locale) =>
      supportedLanguages.contains(locale.languageCode)
      ? locale.languageCode
      : supportedLanguages.first;

  /// Persists first, then schedules.
  ///
  /// If scheduling fails the setting is still what the user chose, and the next
  /// launch re-applies it. Scheduling first would risk a live notification with
  /// nothing on disk to explain it.
  Future<void> _update(Reminder reminder) async {
    final l10n = AppLocalizations.of(context);
    final label = l10n.occasionLabel(reminder.occasion);

    // Asked on the first switch-on rather than at launch, so the prompt arrives
    // attached to an action whose purpose is obvious. Every reminder ships off
    // precisely so that this is the flow.
    if (reminder.enabled && !_reminders[reminder.occasion]!.enabled) {
      final granted = await _scheduler.requestPermission();
      if (!mounted) return;
      if (!granted) {
        setState(() => _permissionDenied = true);
        return;
      }
      setState(() => _permissionDenied = false);
    }

    setState(() => _reminders = {..._reminders, reminder.occasion: reminder});

    await _store.write(reminder);
    await _scheduler.apply(
      reminder,
      channelName: label,
      title: label,
      body: l10n.reminderBody,
    );
  }

  Future<void> _pickTime(Reminder reminder) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.hour, minute: reminder.minute),
    );
    if (picked == null) return;
    await _update(reminder.copyWith(hour: picked.hour, minute: picked.minute));
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
          if (occasion.index == 0 ||
              PrayerOccasion.values[occasion.index - 1].group != occasion.group)
            GroupHeading(
              label: l10n.groupLabel(occasion.group),
              first: occasion.index == 0,
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
              secondary: widget.showTimes
                  ? IconButton(
                      icon: const Icon(Icons.schedule),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).timePickerInputHelpText,
                      onPressed: () => _pickTime(reminder),
                    )
                  : null,
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
          secondary: widget.showTimes
              ? IconButton(
                  icon: const Icon(Icons.schedule),
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).timePickerInputHelpText,
                  onPressed: _pickFastingTime,
                )
              : null,
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
