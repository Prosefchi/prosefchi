import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/calendar_repository.dart';
import '../services/fasting_schedule.dart';
import '../services/notification_service.dart';
import '../services/reminder_store.dart';
import '../services/settings_controller.dart';
import 'prayers_screen.dart';
import 'today_screen.dart';

/// Holds the two top-level destinations.
///
/// The screens are kept alive in an IndexedStack rather than rebuilt on each
/// switch, so moving between them neither re-reads the calendar nor loses a
/// reading position part way down a prayer.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.reminderStore,
    this.scheduler,
    this.calendars,
  });

  /// Injectable so a test can drive the launch refill without touching
  /// preferences or platform channels.
  final ReminderStore? reminderStore;
  final ReminderScheduler? scheduler;
  final CalendarRepository? calendars;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _refilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once per launch, after the locale is available. The fasting reminder is
    // a bounded run of one-off notifications rather than a repeating alarm, so
    // without a refill it quietly runs out after a month or so.
    if (_refilled) return;
    _refilled = true;
    _refillFastingReminders();
  }

  Future<void> _refillFastingReminders() async {
    final l10n = AppLocalizations.of(context);
    final language = SettingsScope.of(context).effectiveLanguage;
    final store = widget.reminderStore ?? PreferencesReminderStore();

    final reminder = await store.readFasting();
    // Nothing to schedule and nothing stale to clear, so do not wake the
    // notification plugin at all on the overwhelmingly common path.
    if (!reminder.enabled) return;

    await refreshFastingReminders(
      reminder: reminder,
      calendars: widget.calendars ?? sharedCalendarRepository,
      scheduler: widget.scheduler ?? NotificationService(),
      language: language,
      l10n: l10n,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [TodayScreen(), PrayersScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            selectedIcon: const Icon(Icons.today),
            label: l10n.today,
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: l10n.prayers,
          ),
        ],
      ),
    );
  }
}
