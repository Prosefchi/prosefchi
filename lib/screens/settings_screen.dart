import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/occasion_labels.dart';
import '../services/calendar_repository.dart' show supportedLanguages;
import '../services/notification_service.dart';
import '../services/reminder_store.dart';
import '../services/settings_controller.dart';
import 'reminders_screen.dart';

/// Language and reminders.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.reminderStore, this.scheduler});

  /// Injectable and passed through to [RemindersScreen], so a test can drive
  /// the whole settings flow without platform channels.
  final ReminderStore? reminderStore;
  final ReminderScheduler? scheduler;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = SettingsScope.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          _Heading(l10n.language),
          RadioGroup<String?>(
            groupValue: settings.language,
            onChanged: (value) => _setLanguage(context, value),
            child: Column(
              children: [
                // Null is a real option, not an absence: following the device
                // is different from having picked English, because the device
                // language can change afterwards.
                RadioListTile<String?>(
                  value: null,
                  title: Text(l10n.languageSystem),
                ),
                for (final language in supportedLanguages)
                  RadioListTile<String?>(
                    value: language,
                    title: Text(_languageName(l10n, language)),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          _Heading(l10n.reminders),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l10n.reminders),
            subtitle: Text(l10n.remindersSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    RemindersScreen(store: reminderStore, scheduler: scheduler),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Changes the language and brings the reminders with it.
  ///
  /// Notification text is baked in when a reminder is scheduled, so switching
  /// language would otherwise leave every pending reminder in the old one until
  /// the user happened to toggle it. The strings for the new language are
  /// loaded directly from the delegate rather than waiting for a rebuild, so
  /// this does not depend on frame timing.
  Future<void> _setLanguage(BuildContext context, String? language) async {
    final settings = SettingsScope.of(context);
    if (language == settings.language) return;

    await settings.setLanguage(language);

    final l10n = await AppLocalizations.delegate.load(
      Locale(settings.effectiveLanguage),
    );
    final store = reminderStore ?? PreferencesReminderStore();
    final notifications = scheduler ?? NotificationService();

    for (final reminder in (await store.readAll()).values) {
      if (!reminder.enabled) continue;
      final label = l10n.occasionLabel(reminder.occasion);
      await notifications.apply(
        reminder,
        channelName: label,
        title: label,
        body: l10n.reminderBody,
      );
    }
  }

  static String _languageName(AppLocalizations l10n, String language) =>
      switch (language) {
        'el' => l10n.languageGreek,
        _ => l10n.languageEnglish,
      };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
