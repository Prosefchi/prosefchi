import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/text_size.dart';
import 'calendar_repository.dart' show languageFor, supportedLanguages;

/// Persists the app-level settings.
///
/// Behind an interface for the same reason as the other stores: so screens can
/// be tested without platform channels.
abstract interface class SettingsStore {
  Future<String?> readLanguage();
  Future<void> writeLanguage(String? language);
  Future<bool> readOnboardingSeen();
  Future<void> writeOnboardingSeen(bool seen);
  Future<String?> readTextSize();
  Future<void> writeTextSize(String slug);
}

class PreferencesSettingsStore implements SettingsStore {
  static const _languageKey = 'settings.language';
  static const _onboardingKey = 'settings.onboardingSeen';
  static const _textSizeKey = 'settings.textSize';

  @override
  Future<String?> readLanguage() async =>
      (await SharedPreferences.getInstance()).getString(_languageKey);

  @override
  Future<void> writeLanguage(String? language) async {
    final preferences = await SharedPreferences.getInstance();
    if (language == null) {
      await preferences.remove(_languageKey);
    } else {
      await preferences.setString(_languageKey, language);
    }
  }

  @override
  Future<bool> readOnboardingSeen() async =>
      (await SharedPreferences.getInstance()).getBool(_onboardingKey) ?? false;

  @override
  Future<void> writeOnboardingSeen(bool seen) async =>
      (await SharedPreferences.getInstance()).setBool(_onboardingKey, seen);

  @override
  Future<String?> readTextSize() async =>
      (await SharedPreferences.getInstance()).getString(_textSizeKey);

  @override
  Future<void> writeTextSize(String slug) async =>
      (await SharedPreferences.getInstance()).setString(_textSizeKey, slug);
}

/// Holds the settings the whole app reads, and notifies when they change.
///
/// Language is nullable on purpose: null means follow the device, which is
/// what someone who never opens settings should get. It is a distinct state
/// from having chosen English, because the device language can change later.
class SettingsController extends ChangeNotifier {
  SettingsController({SettingsStore? store})
    : _store = store ?? PreferencesSettingsStore();

  final SettingsStore _store;

  String? _language;
  bool _onboardingSeen = false;
  TextSize _textSize = TextSize.small;

  /// How large the app draws its text.
  TextSize get textSize => _textSize;

  /// Whether the welcome flow has been completed.
  ///
  /// Drives what the app opens on. Replaying it from settings does not clear
  /// this, so a replay is a replay rather than a downgrade to a first launch.
  bool get onboardingSeen => _onboardingSeen;

  /// The chosen language, or null to follow the device.
  String? get language => _language;

  /// What to hand [WidgetsApp.locale]. Null lets Flutter resolve the device
  /// locale against the supported ones.
  Locale? get locale => _language == null ? null : Locale(_language!);

  /// The language actually in force, resolving null against the device.
  ///
  /// Needed when something has to act on the language outside the widget tree,
  /// such as rescheduling notifications whose text is baked in at schedule
  /// time.
  String get effectiveLanguage => _language ?? deviceLanguage();

  Future<void> load() async {
    final stored = await _store.readLanguage();
    _language = supportedLanguages.contains(stored) ? stored : null;
    _onboardingSeen = await _store.readOnboardingSeen();
    _textSize = TextSize.bySlug(await _store.readTextSize());
    notifyListeners();
  }

  Future<void> setTextSize(TextSize size) async {
    if (size == _textSize) return;
    _textSize = size;
    await _store.writeTextSize(size.slug);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    if (_onboardingSeen) return;
    _onboardingSeen = true;
    await _store.writeOnboardingSeen(true);
    notifyListeners();
  }

  Future<void> setLanguage(String? language) async {
    if (language == _language) return;
    _language = supportedLanguages.contains(language) ? language : null;
    await _store.writeLanguage(_language);
    notifyListeners();
  }

  /// The device's language if we publish it, otherwise English.
  static String deviceLanguage() =>
      languageFor(PlatformDispatcher.instance.locale);
}

/// Makes the controller reachable from any screen, and rebuilds them when it
/// changes.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static SettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'No SettingsScope above this widget');
    return scope!.notifier!;
  }

  /// The controller if there is one, rather than asserting there must be.
  ///
  /// For a screen that reads a setting but does not depend on it — the prayer
  /// screen scales its text by one and is otherwise complete without it. That
  /// keeps it usable from a test, and from anywhere it is shown outside the
  /// app's own tree, without every such caller having to build a scope.
  static SettingsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier;
}
