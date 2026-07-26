import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/markup.dart';
import 'package:prosefchi/screens/markup_paragraph.dart';
import 'package:url_launcher/url_launcher.dart';

import '../support/pump.dart';

Widget harness(
  List<MarkupSpan> spans, {
  Future<bool> Function(Uri, {LaunchMode mode})? launch,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: MarkupParagraph(spans, launch: launch)),
);

void main() {
  testWidgets('opens the target of a tapped link inside the app', (
    tester,
  ) async {
    // The label is what is shown; the target is what a tap has to reach. A
    // rendering that showed one and opened the other would look correct.
    //
    // The mode is asserted alongside it because a link that leaves for another
    // app looks like it worked: it is only on coming back that the reader
    // finds the app was put in the background and the rule closed.
    Uri? opened;
    LaunchMode? how;
    await tester.pumpWidget(
      harness(
        const [MarkupLink(text: 'Source', url: 'https://example.org/rule/')],
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          opened = url;
          how = mode;
          return true;
        },
      ),
    );

    await tester.tap(find.text('Source'));
    await settle(tester);

    expect(opened, Uri.parse('https://example.org/rule/'));
    expect(how, LaunchMode.inAppBrowserView);
  });

  testWidgets('falls back to the platform default', (tester) async {
    // A device with no Custom Tabs provider cannot honour the in-app mode.
    // Opening the link anywhere beats reporting a failure to a reader who can
    // do nothing about it.
    final tried = <LaunchMode>[];
    await tester.pumpWidget(
      harness(
        const [MarkupLink(text: 'Source', url: 'https://example.org/')],
        launch: (url, {mode = LaunchMode.platformDefault}) async {
          tried.add(mode);
          return mode == LaunchMode.platformDefault;
        },
      ),
    );

    await tester.tap(find.text('Source'));
    await settle(tester);

    expect(tried, [LaunchMode.inAppBrowserView, LaunchMode.platformDefault]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('says so when nothing can open the link', (tester) async {
    await tester.pumpWidget(
      harness(const [
        MarkupLink(text: 'Source', url: 'https://example.org/'),
      ], launch: (_, {mode = LaunchMode.platformDefault}) async => false),
    );

    await tester.tap(find.text('Source'));
    await settle(tester);

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('renders the words around a link as one paragraph', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const [
        MarkupPlain('From '),
        MarkupLink(text: 'there', url: 'https://example.org/'),
        MarkupPlain(' only.'),
      ]),
    );

    expect(find.text('From there only.'), findsOneWidget);
  });
}
