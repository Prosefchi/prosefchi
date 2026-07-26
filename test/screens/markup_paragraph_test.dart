import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/markup.dart';
import 'package:prosefchi/screens/markup_paragraph.dart';

import '../support/pump.dart';

Widget harness(List<MarkupSpan> spans, {Future<bool> Function(Uri)? launch}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: MarkupParagraph(spans, launch: launch)),
    );

void main() {
  testWidgets('opens the target of a tapped link', (tester) async {
    // The label is what is shown; the target is what a tap has to reach. A
    // rendering that showed one and opened the other would look correct.
    Uri? opened;
    await tester.pumpWidget(
      harness(
        const [MarkupLink(text: 'Source', url: 'https://example.org/rule/')],
        launch: (url) async {
          opened = url;
          return true;
        },
      ),
    );

    await tester.tap(find.text('Source'));
    await settle(tester);

    expect(opened, Uri.parse('https://example.org/rule/'));
  });

  testWidgets('says so when nothing can open the link', (tester) async {
    await tester.pumpWidget(
      harness(const [
        MarkupLink(text: 'Source', url: 'https://example.org/'),
      ], launch: (_) async => false),
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
