import 'package:flutter/material.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/services/settings_controller.dart';

/// A localized app around [home].
///
/// The three localization arguments were written out in a dozen test files.
/// Nothing here is a decision — it is the boilerplate a screen needs before it
/// can render its own strings.
///
/// A null [locale] means "follow the device", which is a real state and not
/// an absence of one — it is what `SettingsController.locale` returns when no
/// language has been chosen.
Widget localizedApp({
  required Widget home,
  Locale? locale,
  TransitionBuilder? builder,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// A localized app around [home], with [controller]'s settings above it and
/// rebuilding on them.
///
/// For the two screens that read settings and change them in the same breath.
/// The `ListenableBuilder` is outside the scope for the reason `main.dart`
/// gives: an `InheritedNotifier` rebuilds only what reads it, and `MaterialApp`
/// does not, so the locale would not follow a language change without it.
///
/// Loads the controller first, since a screen built before its settings have
/// been read shows the defaults and then changes under the test.
Future<Widget> settingsApp(
  SettingsController controller, {
  required Widget home,
}) async {
  await controller.load();
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SettingsScope(
      controller: controller,
      child: localizedApp(home: home, locale: controller.locale),
    ),
  );
}
