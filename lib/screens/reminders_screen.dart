import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/prayer.dart';
import '../models/reminder.dart';
import '../services/notification_service.dart';
import '../services/reminder_store.dart';

/// Switches each prayer reminder on or off and sets its time.
///
/// Every occasion is independent. Someone who wants only the evening reminder
/// gets only the evening reminder, and because each has its own Android
/// channel they can also silence one from system settings without losing the
/// rest.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, this.store, this.scheduler});

  /// Injectable so tests need neither real preferences nor platform channels.
  final ReminderStore? store;
  final ReminderScheduler? scheduler;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late final ReminderStore _store = widget.store ?? PreferencesReminderStore();
  late final ReminderScheduler _scheduler =
      widget.scheduler ?? NotificationService();

  Map<PrayerOccasion, Reminder> _reminders = {};
  bool _loading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reminders = await _store.readAll();
    if (!mounted) return;
    setState(() {
      _reminders = reminders;
      _loading = false;
    });
  }

  /// Persists first, then schedules.
  ///
  /// If scheduling fails the setting is still what the user chose, and the next
  /// launch re-applies it. Scheduling first would risk a live notification with
  /// nothing on disk to explain it.
  Future<void> _update(Reminder reminder) async {
    final l10n = AppLocalizations.of(context);
    final label = labelFor(l10n, reminder.occasion);

    // Ask only when switching one on, so the prompt arrives attached to an
    // action whose purpose is obvious.
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reminders)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                for (final occasion in PrayerOccasion.values)
                  if (_reminders[occasion] case final reminder?)
                    SwitchListTile(
                      value: reminder.enabled,
                      onChanged: (enabled) =>
                          _update(reminder.copyWith(enabled: enabled)),
                      title: Text(labelFor(l10n, occasion)),
                      subtitle: Text(
                        reminder.enabled
                            ? _formatTime(context, reminder)
                            : l10n.reminderOff,
                      ),
                      secondary: IconButton(
                        icon: const Icon(Icons.schedule),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).timePickerInputHelpText,
                        onPressed: () => _pickTime(reminder),
                      ),
                    ),
              ],
            ),
    );
  }

  /// Uses the locale's own clock convention rather than forcing 24 hour.
  static String _formatTime(BuildContext context, Reminder reminder) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: reminder.hour, minute: reminder.minute),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
}

/// The display name of an occasion.
///
/// Shared with the prayers list so the two never disagree about what a rule is
/// called, which would be visible when a notification arrives.
String labelFor(AppLocalizations l10n, PrayerOccasion occasion) =>
    switch (occasion) {
      PrayerOccasion.morning => l10n.prayerMorning,
      PrayerOccasion.midday => l10n.prayerMidday,
      PrayerOccasion.night => l10n.prayerNight,
      PrayerOccasion.compline => l10n.prayerCompline,
      PrayerOccasion.beforeMeal => l10n.prayerBeforeMeal,
      PrayerOccasion.afterMeal => l10n.prayerAfterMeal,
      PrayerOccasion.beforeCommunion => l10n.prayerBeforeCommunion,
      PrayerOccasion.afterCommunion => l10n.prayerAfterCommunion,
    };
