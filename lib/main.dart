import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'screens/home_shell.dart';
import 'services/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loaded before the first frame so the app never paints in one language and
  // then switches to another.
  final settings = SettingsController();
  await settings.load();

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
        home: const HomeShell(),
      ),
    ),
  );
}
