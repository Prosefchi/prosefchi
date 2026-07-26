import 'package:flutter_test/flutter_test.dart';

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` cannot be used in this app's widget tests: it runs until no
/// frame is scheduled, and a loading spinner schedules one forever, so it spins
/// until its own timeout instead of returning.
Future<void> settle(WidgetTester tester, {int frames = 25}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
