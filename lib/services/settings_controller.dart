import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_repository.dart' show supportedLanguages;

/// Persists the app-level settings.
///
/// Behind an interface for the same reason as the other stores: so screens can
/// be tested without platform channels.
abstract interface class SettingsStore {
  Future<String?> readLanguage();
  Future<void> writeLanguage(String? language);
}

class PreferencesSettingsStore implements SettingsStore {
  static const _key = 'settings.language';

  @override
  Future<String?> readLanguage() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> writeLanguage(String? language) async {
    final preferences = await SharedPreferences.getInstance();
    if (language == null) {
      await preferences.remove(_key);
    } else {
      await preferences.setString(_key, language);
    }
  }
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
    notifyListeners();
  }

  Future<void> setLanguage(String? language) async {
    if (language == _language) return;
    _language = supportedLanguages.contains(language) ? language : null;
    await _store.writeLanguage(_language);
    notifyListeners();
  }

  /// The device's language if we publish it, otherwise English.
  static String deviceLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return supportedLanguages.contains(code) ? code : supportedLanguages.first;
  }
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
}
