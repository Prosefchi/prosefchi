import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/calendar_repository.dart';
import '../services/notification_service.dart';
import '../services/reminder_refresh.dart';
import '../services/reminder_store.dart';
import '../services/settings_controller.dart';
import 'about_section.dart';
import 'onboarding_screen.dart';
import 'reminders_screen.dart';

/// Language and reminders.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.reminderStore,
    this.scheduler,
    this.calendars,
    this.about,
  });

  /// Injectable and passed through to [RemindersScreen], so a test can drive
  /// the whole settings flow without platform channels.
  final ReminderStore? reminderStore;
  final ReminderScheduler? scheduler;

  /// Read when the language changes, so the rescheduled fasting reminders carry
  /// the Archdiocese's wording in the language now selected.
  final CalendarRepository? calendars;

  /// Substituted in tests, where the about section's platform channels are
  /// unavailable.
  final Widget? about;

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
          _Heading(l10n.textSize),
          RadioGroup<TextSize>(
            groupValue: settings.textSize,
            onChanged: (value) {
              if (value != null) settings.setTextSize(value);
            },
            child: Column(
              children: [
                for (final size in TextSize.values)
                  RadioListTile<TextSize>(
                    value: size,
                    // Each option drawn at the size it selects, so the choice
                    // shows what it does rather than describing it. The one
                    // that reads comfortably is the one to pick.
                    title: Text(
                      _textSizeName(l10n, size),
                      textScaler: TextScaler.linear(size.scale),
                    ),
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
                builder: (_) => RemindersScreen(
                  store: reminderStore,
                  scheduler: scheduler,
                  calendars: calendars,
                ),
              ),
            ),
          ),
          // Set apart: replaying the welcome is a different kind of thing from
          // the settings above it.
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.waving_hand_outlined),
            title: Text(l10n.showWelcomeAgain),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OnboardingScreen(
                  reminderStore: reminderStore,
                  scheduler: scheduler,
                ),
              ),
            ),
          ),
          const Divider(height: 32),
          _Heading(l10n.about),
          about ?? const AboutSection(),
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
  ///
  /// Reschedules through the shared refresh rather than looping over the prayer
  /// reminders here, which used to leave the fasting block in the old language
  /// until the next launch.
  Future<void> _setLanguage(BuildContext context, String? language) async {
    final settings = SettingsScope.of(context);
    if (language == settings.language) return;

    await settings.setLanguage(language);

    await refreshReminders(
      store: reminderStore ?? PreferencesReminderStore(),
      calendars: calendars ?? sharedCalendarRepository,
      scheduler: scheduler ?? sharedReminderScheduler,
      language: settings.effectiveLanguage,
      l10n: await AppLocalizations.delegate.load(
        Locale(settings.effectiveLanguage),
      ),
    );
  }

  static String _languageName(AppLocalizations l10n, String language) =>
      switch (language) {
        'el' => l10n.languageGreek,
        _ => l10n.languageEnglish,
      };

  static String _textSizeName(AppLocalizations l10n, TextSize size) =>
      switch (size) {
        TextSize.small => l10n.textSizeSmall,
        TextSize.medium => l10n.textSizeMedium,
        TextSize.large => l10n.textSizeLarge,
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
