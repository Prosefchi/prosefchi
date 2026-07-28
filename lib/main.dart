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

  // Neither kind of reminder is a standing alarm, so opening the app has to
  // re-arm them. Owned here rather than by a screen: it is not a navigation
  // concern, and a screen would only cover the states in which it is mounted —
  // the app opens on the welcome flow until that is done, and reminders can be
  // switched on there.
  //
  // Not held in a variable and not awaited. Its lifecycle listener registers
  // with the binding, which keeps both alive for as long as the app runs, and
  // nothing on the first frame depends on the refresh finishing.
  ReminderRefresher(settings: settings).start();

  runApp(ProsefchiApp(settings: settings));
}

/// The flag's crimson, which both themes are built out of.
const _seed = Color(0xFF7B1113);

/// Built once each, not per build.
///
/// Both are constant, and rebuilding them costs twice over: `ColorScheme
/// .fromSeed` runs a palette quantizer, and the state-resolved scrollbar
/// properties are closures that never compare equal, so a fresh `ThemeData`
/// is never `==` the last one. `MaterialApp` reads that as a theme change and
/// runs a 200ms `AnimatedTheme` transition — 26 extra relayouts of the page —
/// every time a setting changes. Changing the text size is exactly when the
/// page is most expensive to lay out.
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
        // A null locale lets Flutter resolve the device's, which is what
        // someone who never opens settings should get.
        locale: settings.locale,
        // onGenerateTitle rather than title: the name differs by language, and
        // the localization delegates are not resolved yet when `title` is read.
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _lightTheme,
        darkTheme: _darkTheme,
        // The welcome flow is the home widget until it is done, rather than a
        // route pushed over the app, so there is no frame where the app shows
        // behind it and nothing to dismiss it past.
        home: settings.onboardingSeen
            ? const HomeShell()
            : const OnboardingScreen(),
      ),
    ),
  );
}
