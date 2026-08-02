// Holds the app's labels to the keys the website looks its strings up by.
//
// The site falls back to the key itself when a string is missing, so an ARB
// entry renamed under it renders `fastAllowanceStrict` into the page and
// nothing says so. The app is the side the compiler checks, so checking it
// against the same keys is what catches that.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/l10n/app_localizations.dart';
import 'package:prosefchi/l10n/liturgical_keys.dart';
import 'package:prosefchi/l10n/liturgical_labels.dart';
import 'package:prosefchi/liturgics/fasting.dart';
import 'package:prosefchi/models/calendar.dart';

void main() {
  for (final language in supportedLanguages) {
    group(language, () {
      late Map<String, dynamic> arb;
      late AppLocalizations l10n;

      setUp(() async {
        arb =
            jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
                as Map<String, dynamic>;
        l10n = await AppLocalizations.delegate.load(Locale(language));
      });

      test('every fasting allowance is named in the ARB', () {
        for (final allowance in FastAllowance.values) {
          expect(
            arb[fastAllowanceKey(allowance)],
            l10n.fastAllowanceLabel(allowance),
            reason: fastAllowanceKey(allowance),
          );
        }
      });

      test('every fasting season is named in the ARB', () {
        for (final season in FastSeason.values) {
          expect(
            arb[fastSeasonKey(season)],
            l10n.fastSeasonLabel(season),
            reason: fastSeasonKey(season),
          );
        }
      });

      test('every day mark is named in the ARB', () {
        for (final mark in DayMark.values) {
          expect(
            arb[dayMarkKey(mark)],
            l10n.dayMarkLabel(mark),
            reason: dayMarkKey(mark),
          );
        }
      });

      test('every tone is named in the ARB', () {
        for (var tone = 1; tone <= 8; tone++) {
          expect(
            arb[toneKey(tone)],
            l10n.toneLabel(tone),
            reason: toneKey(tone),
          );
        }
      });
    });
  }
}
