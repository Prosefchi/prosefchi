import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/screens/about_section.dart';
import '../support/pump.dart';

PackageInfo info({String version = '1.2.3', String build = '7'}) => PackageInfo(
  appName: 'Orthodox Prayer',
  packageName: 'io.github.prosefchi.prosefchi',
  version: version,
  buildNumber: build,
);

Widget harness({
  Future<PackageInfo> Function()? packageInfo,
  Future<bool> Function(Uri)? launch,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ListView(
      children: [
        AboutSection(
          packageInfo: packageInfo ?? () async => info(),
          launch: launch ?? (_) async => true,
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
        launch: (url) async {
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
    await tester.pumpWidget(harness(launch: (_) async => false));
    await settle(tester);

    await tester.tap(find.text('Source code'));
    await settle(tester);

    expect(find.text('Could not open the link'), findsOneWidget);
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
