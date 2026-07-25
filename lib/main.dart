import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'screens/today_screen.dart';

void main() => runApp(const ProsefchiApp());

class ProsefchiApp extends StatelessWidget {
  const ProsefchiApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    // onGenerateTitle rather than title: the name differs by language, and the
    // localization delegates are not resolved yet when `title` is read.
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
    home: const TodayScreen(),
  );
}
