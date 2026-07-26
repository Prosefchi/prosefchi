import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
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
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF7B1113),
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF7B1113),
          brightness: Brightness.dark,
        ),
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
