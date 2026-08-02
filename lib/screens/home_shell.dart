import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/reminder.dart';
import '../services/calendar_repository.dart' show languageFor;
import '../services/notification_service.dart';
import '../services/prayer_repository.dart';
import 'prayers_screen.dart';
import 'today_screen.dart';

/// Holds the two top-level destinations, and answers a tapped reminder.
///
/// Kept alive in an IndexedStack, so switching tabs neither re-reads the
/// calendar nor loses a reading position part way down a prayer. Tap routing
/// belongs here because it is navigation; re-arming the schedule does not.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.scheduler, this.prayers});

  final ReminderScheduler? scheduler;
  final PrayerRepository? prayers;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _today = 0;
  static const _prayers = 1;

  int _index = _today;

  late final ReminderScheduler _scheduler =
      widget.scheduler ?? sharedReminderScheduler;
  late final PrayerRepository _repository =
      widget.prayers ?? sharedPrayerRepository;

  StreamSubscription<ReminderTarget>? _taps;
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than initState because opening a rule needs the locale, and
    // once rather than on every dependency change.
    if (_listening) return;
    _listening = true;
    _taps = _scheduler.taps.listen(_open);
    _openLaunchTarget();
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  /// A tap that started the app, which arrives before anything is listening.
  Future<void> _openLaunchTarget() async {
    if (await _scheduler.takeLaunchTarget() case final target?) _open(target);
  }

  /// Opens what the reminder was reminding them of.
  Future<void> _open(ReminderTarget target) async {
    if (!mounted) return;

    switch (target) {
      // The day is where the fasting rule is shown, so the tab is the answer.
      case FastingTarget():
        setState(() => _index = _today);

      case PrayerTarget(:final occasion):
        // The tab first, so Back lands on the list rather than on the day.
        setState(() => _index = _prayers);

        final set = await _repository.load(
          occasion,
          languageFor(Localizations.localeOf(context)),
        );
        if (!mounted) return;
        // A rule still awaiting text would open an empty page; the list
        // disables those, and stopping on it is the same answer.
        if (set == null || !set.hasContent) return;

        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => PrayerScreen(set: set)));
    }
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
