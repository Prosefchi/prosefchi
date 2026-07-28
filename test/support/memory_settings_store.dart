import 'package:prosefchi/services/settings_controller.dart';

/// A [SettingsStore] held in memory.
///
/// Shared rather than copied per test file. There were two copies, and adding
/// a setting meant remembering both — which is the drift the other doubles in
/// this directory exist to avoid. A `dart:io` store is not an option anyway:
/// `testWidgets` runs inside a `FakeAsync` zone where a real filesystem future
/// never completes, so the test hangs rather than fails.
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore({
    this.language,
    this.onboardingSeen = false,
    this.textSize,
  });

  String? language;
  bool onboardingSeen;
  String? textSize;

  @override
  Future<String?> readLanguage() async => language;

  @override
  Future<void> writeLanguage(String? value) async => language = value;

  @override
  Future<bool> readOnboardingSeen() async => onboardingSeen;

  @override
  Future<void> writeOnboardingSeen(bool seen) async => onboardingSeen = seen;

  @override
  Future<String?> readTextSize() async => textSize;

  @override
  Future<void> writeTextSize(String slug) async => textSize = slug;
}
