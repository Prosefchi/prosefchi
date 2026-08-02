import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'screens/reading_scrollbar.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/reminder_refresh.dart';
import 'services/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loaded before the first frame so the app never paints in one language and
  // then switches to another.
  final settings = SettingsController();
  await settings.load();

  // Owned here rather than by a screen, whose coverage would be whatever
  // navigation reaches. Not held or awaited: the lifecycle listener registers
  // with the binding, which keeps it alive as long as the app runs.
  ReminderRefresher(settings: settings).start();

  runApp(ProsefchiApp(settings: settings));
}

/// The flag's crimson, which both themes are built out of.
const _seed = Color(0xFF7B1113);

/// Built once each, not per build. The state-resolved scrollbar properties are
/// closures that never compare equal, so a fresh `ThemeData` is never `==` the
/// last: `MaterialApp` reads that as a theme change and runs a 200ms
/// `AnimatedTheme` on every settings change.
final _lightTheme = _theme(Brightness.light);
final _darkTheme = _theme(Brightness.dark);

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    scrollbarTheme: readingScrollbarTheme(scheme),
  );
}

class ProsefchiApp extends StatelessWidget {
  const ProsefchiApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Outside the scope rather than inside it, so that MaterialApp itself is
    // rebuilt when the language changes. An InheritedNotifier only rebuilds
    // widgets that read it, and MaterialApp does not.
    listenable: settings,
    builder: (context, _) => SettingsScope(
      controller: settings,
      child: MaterialApp(
        // Null lets Flutter resolve the device's.
        locale: settings.locale,
        // onGenerateTitle rather than title: the name differs by language, and
        // the localization delegates are not resolved yet when `title` is read.
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _lightTheme,
        darkTheme: _darkTheme,
        // The home widget rather than a route pushed over the app, so there is
        // no frame where the app shows behind it and nothing to dismiss past.
        home: settings.onboardingSeen
            ? const HomeShell()
            : const OnboardingScreen(),
      ),
    ),
  );
}
