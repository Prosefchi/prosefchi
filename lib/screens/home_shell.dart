import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'prayers_screen.dart';
import 'today_screen.dart';

/// Holds the two top-level destinations.
///
/// The screens are kept alive in an IndexedStack rather than rebuilt on each
/// switch, so moving between them does not re-read the calendar or lose a
/// reading position part way down a prayer.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

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
