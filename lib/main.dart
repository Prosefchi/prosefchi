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

/// The flag's crimson, which both themes are built out of.
const _seed = Color(0xFF7B1113);

/// Applies the chosen text size on top of the platform's own.
///
/// Multiplying rather than replacing is the point. Someone who has already set
/// a system text size has said what they need, and an app that overwrites that
/// with its own idea of "small" takes it away from exactly the reader this
/// setting exists for.
class _ScaledBy extends TextScaler {
  const _ScaledBy(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  // Deprecated on TextScaler but still abstract there, so a subclass has to
  // supply it. Nothing here calls it; [scale] is what does the work, and it is
  // the one that stays correct if the platform ever scales non-linearly.
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _ScaledBy && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    // A pill rather than Material's hairline. There is no separate widget for
    // one: a Scrollbar becomes a pill by being thick, fully rounded and never
    // allowed below a length a thumb can land on.
    //
    // The minimum length is what makes this work at the large text size. The
    // thumb is drawn in proportion to the content, so the longest rule at the
    // largest text would otherwise taper to a few unusable pixels — the point
    // at which a scrollbar stops being a way through a document.
    //
    // It fattens while dragged, the way Cupertino's does, so the thing under
    // the finger is the thing that answers. Material's default thumb is a flat
    // grey that comes out near-white on the dark theme, where it reads as a
    // foreign object laid over the page; drawing it from the scheme keeps it
    // the app's own colour in both.
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.dragged) ? 12 : 8,
      ),
      radius: const Radius.circular(12),
      minThumbLength: 56,
      mainAxisMargin: 8,
      crossAxisMargin: 4,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) return scheme.primary;
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: 0.7);
        }
        return scheme.primary.withValues(alpha: 0.45);
      }),
    ),
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
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        // Wrapped around every route rather than applied on the prayer screen,
        // because a text size someone needs in order to read is not a
        // preference about prayers. It has to reach the settings screen that
        // sets it, too, or the control is unreadable to whoever needs it most.
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: _ScaledBy(media.textScaler, settings.textSize.scale),
            ),
            child: child!,
          );
        },
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
