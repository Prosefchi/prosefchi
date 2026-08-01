import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/calendar.dart' show supportedLanguages;
import 'package:prosefchi/models/site.dart';

import '../../tool/build_site.dart';
import '../support/authored_document.dart';

/// A line opening a Markdown list, in any of the three ways it can be written.
final _listMarker = RegExp(r'^\s*([-*+]\s|\d+\.\s)');

/// Checks the authored documents the site renders and the paths it writes them
/// at, rather than the generator's plumbing.
///
/// Google Play's listing links to the policy and the app opens it, so a missing
/// translation or a moved path would be found by a reader hitting a 404.
void main() {
  group('privacy policy', () {
    test('English keeps the bare name, and every language has one', () {
      // Where GitHub renders one from, and where the store listing points.
      expect(privacySource('en'), 'PRIVACY.md');
      expect(privacySource('el'), 'PRIVACY.el.md');

      for (final language in supportedLanguages) {
        expectAuthoredDocument(privacySource(language));
      }
    });

    test('carries no list markers', () {
      // The parser joins consecutive lines into one paragraph, so a list
      // arrives as a run-on sentence with hyphens through it.
      for (final language in supportedLanguages) {
        final path = privacySource(language);
        final offenders = File(
          path,
        ).readAsLinesSync().where(_listMarker.hasMatch);

        expect(
          offenders,
          isEmpty,
          reason: '$path has a list, which renders as a run-on paragraph',
        );
      }
    });

    test('sits where Google Play was told it does', () {
      // Through the same function the app's about section opens, rather than a
      // lookalike composed here. Nothing rebuilds the store listing.
      expect(
        privacyPolicyUrl('en').toString(),
        'https://prosefchi.org/about/privacy/',
      );
      expect(privacyPagePath('el'), 'el/about/privacy/');
    });
  });
}
