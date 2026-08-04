import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Checks the icon masters in `assets/icon/`, not any rendering of them.
///
/// The four SVGs are one artwork at two insets and two golds, so they share
/// the traced firesteel path verbatim. Nothing regenerates them: they are
/// committed output, and an edit to one is an edit to one.
void main() {
  final masters = [
    'icon.svg',
    'icon-flat.svg',
    'adaptive_foreground.svg',
    'adaptive_monochrome.svg',
  ];

  String read(String name) => File('assets/icon/$name').readAsStringSync();

  String firesteel(String svg) {
    final match = RegExp(r'<path id="firesteel" d="([^"]+)"').firstMatch(svg);
    expect(match, isNotNull, reason: 'no #firesteel path');
    return match!.group(1)!;
  }

  test('every master and the PNGs rendered from them exist', () {
    for (final name in [
      ...masters,
      'icon.png',
      'adaptive_foreground.png',
      'adaptive_monochrome.png',
    ]) {
      expect(
        File('assets/icon/$name').existsSync(),
        isTrue,
        reason: 'assets/icon/$name is missing',
      );
    }
  });

  test('the firesteel is the same path in all four', () {
    final paths = {for (final name in masters) name: firesteel(read(name))};
    expect(
      paths.values.toSet(),
      hasLength(1),
      reason:
          'the masters have drifted apart; they are one traced shape and the '
          'trace is accurate to well under a pixel, so re-emit rather than '
          'reconcile by hand',
    );
  });

  test('the themed-icon mask carries neither the shadow nor the ramp', () {
    // Android reads only this layer's alpha, so a shadow in it is not a
    // shadow: it is more cross, in the launcher's own tint.
    final mono = read('adaptive_monochrome.svg');
    expect(mono, isNot(contains('feGaussianBlur')));
    expect(mono, isNot(contains('linearGradient')));
  });

  test('pubspec points the monochrome key at its own file', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('adaptive_icon_monochrome: assets/icon/adaptive_monochrome.png'),
    );
  });
}
