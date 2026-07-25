import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/screens/prayers_screen.dart';
import 'package:prosefchi/services/prayer_repository.dart';

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.contents);

  final Map<String, String> contents;

  @override
  Future<ByteData> load(String key) async {
    final value = contents[key];
    if (value == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(utf8.encode(value));
  }
}

const morning = '''
# Morning Prayers

> On rising from sleep, make the sign of the Cross.

## The Beginning

In the name of the Father, and of the Son, and of the Holy Spirit. Amen.
''';

const placeholderMidday = '''
# Midday Prayers

> [Awaiting text: the midday rule.]
''';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget harness(Map<String, String> assets, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PrayersScreen(
        repository: PrayerRepository(bundle: _FakeBundle(assets)),
      ),
    );

void main() {
  testWidgets('lists every rule', (tester) async {
    await tester.pumpWidget(harness({'res/prayers/morning_en.md': morning}));
    await settle(tester);

    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Midday'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);
  });

  testWidgets('marks a rule with no text unavailable and does not open it', (
    tester,
  ) async {
    // A stub must never be presented as though it were an abbreviated prayer.
    await tester.pumpWidget(
      harness({
        'res/prayers/morning_en.md': morning,
        'res/prayers/midday_en.md': placeholderMidday,
      }),
    );
    await settle(tester);

    expect(
      find.text('Not yet available'),
      findsNWidgets(PrayerOccasion.values.length - 1),
      reason: 'every rule but morning is unavailable',
    );

    await tester.tap(find.text('Midday'));
    await settle(tester);

    expect(find.text('Midday Prayers'), findsNothing);
  });

  testWidgets('opens a rule that has real text alongside a marked gap', (
    tester,
  ) async {
    // The morning rule holds the Trisagion and a gap awaiting the rest. The
    // gap must not withhold the part that is ready.
    const partial = '$morning\n> [Awaiting text: the rest of the rule.]\n';
    await tester.pumpWidget(harness({'res/prayers/morning_en.md': partial}));
    await settle(tester);

    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(find.text('The Beginning'), findsOneWidget);
    expect(find.text('[Awaiting text: the rest of the rule.]'), findsOneWidget);
  });

  testWidgets('opens a rule and renders its blocks', (tester) async {
    await tester.pumpWidget(harness({'res/prayers/morning_en.md': morning}));
    await settle(tester);

    await tester.tap(find.text('Morning'));
    await settle(tester);

    expect(find.text('Morning Prayers'), findsOneWidget);
    expect(find.text('The Beginning'), findsOneWidget);
    expect(find.text('On rising from sleep, make the sign of the Cross.'), findsOneWidget);
    expect(
      find.text('In the name of the Father, and of the Son, and of the Holy Spirit. Amen.'),
      findsOneWidget,
    );
  });

  testWidgets('labels the rules in Greek under the el locale', (tester) async {
    await tester.pumpWidget(
      harness({
        'res/prayers/morning_el.md': '# Πρωινὲς Προσευχές\n\nἈμήν.\n',
      }, locale: const Locale('el')),
    );
    await settle(tester);

    expect(find.text('Προσευχές'), findsOneWidget);
    expect(find.text('Πρωί'), findsOneWidget);
    expect(
      find.text('Δεν είναι ακόμη διαθέσιμο'),
      findsNWidgets(PrayerOccasion.values.length - 1),
    );
  });
}
