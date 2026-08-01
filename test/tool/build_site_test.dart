import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/calendar.dart' show supportedLanguages;
import 'package:prosefchi/models/site.dart';

import '../../tool/build_site.dart';
import '../support/authored_document.dart';

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

  group('web app manifest', () {
    // A project-site path, where an absolute value would land outside the site.
    // On prosefchi.org it would happen to work.
    const base = 'https://example.test/prosefchi/';

    Uri from(String language, String value) => Uri.parse(
      '$base${prefixFor(language)}manifest.webmanifest',
    ).resolve(value);

    late Map<String, Map<String, String>> strings;
    setUpAll(() async => strings = await siteStrings());

    Map<String, dynamic> manifest(String language) =>
        jsonDecode(webManifest(strings: strings[language]!, language: language))
            as Map<String, dynamic>;

    // Nothing else reads the key, so a missing one ships as null.
    test('says what the app is in every language', () {
      for (final language in supportedLanguages) {
        expect(
          manifest(language)['description'],
          isNotEmpty,
          reason: 'appDescription is missing for $language',
        );
      }
    });

    // Only the prefixed languages exercise anything: English resolves to the
    // root either way, so a `/`-rooted mistake would pass there.
    test('opens its own language and is scoped to the whole site', () {
      expect(
        from('el', manifest('el')['start_url'] as String).toString(),
        '${base}el/',
        reason: 'two start URLs is what makes them two installed apps',
      );

      for (final language in supportedLanguages.skip(1)) {
        expect(
          from(language, manifest(language)['scope'] as String).toString(),
          base,
          reason: '$language is scoped away from the site root',
        );

        for (final icon
            in (manifest(language)['icons'] as List<dynamic>)
                .cast<Map<String, dynamic>>()) {
          final src = icon['src'] as String;
          expect(from(language, src).toString(), '$base${src.split('/').last}');
        }
      }
    });

    // Checked in rather than generated, and a manifest naming a missing file
    // fails cache.addAll, which leaves no service worker at all.
    test('every icon it names is in the repository', () {
      for (final name in iconFiles) {
        expect(File('site/$name').existsSync(), isTrue, reason: 'site/$name');
      }
    });
  });

  // All that joins the authored markup to the script. Renamed in one and not
  // the other, the badge never appears — which looks like the browser not
  // offering an install.
  test('every download document carries what the install script looks for', () {
    for (final language in supportedLanguages) {
      final source = File(downloadSource(language)).readAsStringSync();
      for (final hook in [
        installSectionClass,
        '<button',
        'data-how="ios"',
        'data-how="mac"',
        'data-how="other"',
      ]) {
        expect(
          source,
          contains(hook),
          reason: '${downloadSource(language)} is missing $hook',
        );
      }
    }
  });
}
