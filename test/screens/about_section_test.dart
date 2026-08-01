import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:prosefchi/screens/about_section.dart';
import '../support/app.dart';
import '../support/pump.dart';

PackageInfo info({String version = '1.2.3', String build = '7'}) => PackageInfo(
  appName: 'Orthodox Prayer',
  packageName: 'io.github.prosefchi.prosefchi',
  version: version,
  buildNumber: build,
);

Widget harness({
  Future<PackageInfo> Function()? packageInfo,
  Future<bool> Function(Uri, {LaunchMode mode})? launch,
  Locale locale = const Locale('en'),
}) => localizedApp(
  locale: locale,
  home: Scaffold(
    body: ListView(
      children: [
        AboutSection(
          packageInfo: packageInfo ?? () async => info(),
          launch:
              launch ?? (_, {mode = LaunchMode.platformDefault}) async => true,
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('shows the version read from the bundle', (tester) async {
    // Read rather than restated, so it cannot drift from pubspec.yaml.
    await tester.pumpWidget(harness());
    await settle(tester);

    expect(find.text('1.2.3 (7)'), findsOneWidget);
  });

  testWidgets('opens the repository', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      harness(
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          opened.add(url);
          return true;
        },
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Source code'));
    await settle(tester);

    expect(opened, [Uri.parse('https://github.com/Prosefchi/prosefchi')]);
  });

  testWidgets('says so when the link cannot be opened', (tester) async {
    // A device with no browser. Rare, but silence would look like a dead row.
    await tester.pumpWidget(
      harness(launch: (_, {mode = LaunchMode.platformDefault}) async => false),
    );
    await settle(tester);

    await tester.tap(find.text('Source code'));
    await settle(tester);

    expect(find.text('Could not open the link'), findsOneWidget);
  });

  testWidgets('opens the privacy policy on the website', (tester) async {
    // Google Play requires this link to work, and the store listing points at
    // the same page, so the URL is worth stating in a test rather than trusting
    // to a build that would only fail on the website.
    final opened = <Uri>[];
    await tester.pumpWidget(
      harness(
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          opened.add(url);
          return true;
        },
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Privacy policy'));
    await settle(tester);

    expect(opened, [Uri.parse('https://prosefchi.org/about/privacy/')]);
  });

  testWidgets('sends a Greek reader to the Greek policy', (tester) async {
    // The same document in the only language they can read it in. The site
    // writes both from the same two constants this resolves, so the two cannot
    // disagree about where the page is.
    final opened = <Uri>[];
    await tester.pumpWidget(
      harness(
        locale: const Locale('el'),
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          opened.add(url);
          return true;
        },
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Πολιτική απορρήτου'));
    await settle(tester);

    expect(opened, [Uri.parse('https://prosefchi.org/el/about/privacy/')]);
  });

  testWidgets('opens the policy in the in-app browser', (tester) async {
    // Not the repository's external browser: a policy is read and returned
    // from, so closing it should put the reader back in settings.
    final modes = <LaunchMode>[];
    await tester.pumpWidget(
      harness(
        launch: (_, {mode = LaunchMode.platformDefault}) async {
          modes.add(mode);
          return true;
        },
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Privacy policy'));
    await settle(tester);

    expect(modes, [LaunchMode.inAppBrowserView]);
  });

  testWidgets('opens the licence page', (tester) async {
    await tester.pumpWidget(harness());
    await settle(tester);

    await tester.tap(find.text('Open source licences'));
    await settle(tester);

    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('survives the version being unavailable', (tester) async {
    // Not worth failing the screen over; the row stays quiet.
    await tester.pumpWidget(
      harness(packageInfo: () async => throw Exception('no platform')),
    );
    await settle(tester);

    expect(find.text('Version'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('labels the section in Greek', (tester) async {
    await tester.pumpWidget(harness(locale: const Locale('el')));
    await settle(tester);

    expect(find.text('Πηγαίος κώδικας'), findsOneWidget);
    expect(find.text('Έκδοση'), findsOneWidget);
    expect(find.text('Άδειες ανοιχτού κώδικα'), findsOneWidget);
  });
}
