import 'package:flutter/widgets.dart';
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

/// Sizes the test surface, undoing it afterwards.
///
/// The default is 800x600 and several screens are taller. A `ListView` does
/// not build what it cannot show, so a `tap` on a row below the fold misses
/// silently and reports itself as a state assertion, with the real cause only
/// in a `warnIfMissed` line further up. Made taller rather than scrolled, for
/// that reason.
///
/// Shared because the three lines were copied into seven tests before this
/// existed, and the next test to need them could not find them.
void surface(WidgetTester tester, Size size, {double pixelRatio = 3.0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
}

/// Tall enough for any single screen in the app to be built in full.
const tallSurface = Size(1170, 5200);

/// About the narrowest phone the app ships to, where a larger text size runs
/// out of width first.
const narrowSurface = Size(1080, 2400);
