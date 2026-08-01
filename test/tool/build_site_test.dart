import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// From the models layer, not services/calendar_repository.dart, which re-exports
// it for the screens but carries Flutter and http with it. This file is about
// the Flutter-free document pipeline and has no business reaching through a
// service to reach a constant.
import 'package:prosefchi/models/calendar.dart' show supportedLanguages;
import 'package:prosefchi/models/markup.dart';
import 'package:prosefchi/models/site.dart';

import '../../tool/build_site.dart';

/// A line opening a Markdown list, in any of the three ways it can be written.
final _listMarker = RegExp(r'^\s*([-*+]\s|\d+\.\s)');

/// Checks the authored documents the site renders and the paths it writes them
/// at, rather than the generator's plumbing.
///
/// The privacy policy is the one page on the site something outside this
/// repository depends on: Google Play's listing links to it, and the app's
/// about section opens it. A missing translation, a document that parses to
/// nothing, or a path that moved would all be found by a reader hitting a 404
/// rather than by anything here, so they are pinned.
void main() {
  group('privacy policy', () {
    test('every language has one, and English keeps the bare name', () {
      // PRIVACY.md is where GitHub renders one from and where a store listing
      // is pointed by hand.
      expect(privacySource('en'), 'PRIVACY.md');
      expect(privacySource('el'), 'PRIVACY.el.md');

      for (final language in supportedLanguages) {
        final path = privacySource(language);
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
      }
    });

    test('each parses to a titled document with prose in it', () {
      for (final language in supportedLanguages) {
        final path = privacySource(language);
        final document = MarkupDocument.parse(File(path).readAsStringSync());

        expect(document.title, isNotEmpty, reason: '$path has no title');
        expect(
          document.hasContent,
          isTrue,
          reason: '$path has no prose, only headings or notes',
        );
      }
    });

    test('carries no list markers', () {
      // The parser joins consecutive lines into one paragraph, so a list
      // authored in the ordinary way arrives on the website as a run-on
      // sentence with hyphens through it. Nothing renders it as a list, so the
      // rule is that the document does not use one.
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
      // Every page and link resolves `privacyPagePath`, so this pins it to the
      // URL handed to the store listing rather than to itself. The listing is
      // the one reader of it that nothing here rebuilds.
      expect(privacyPagePath('en'), 'about/privacy/');
      expect(privacyPagePath('el'), 'el/about/privacy/');
      expect(
        siteUrl.resolve(privacyPagePath('en')).toString(),
        'https://prosefchi.org/about/privacy/',
      );
    });
  });
}
