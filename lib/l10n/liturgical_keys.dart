// The ARB key naming each liturgical value, for the app and the website both.
//
// The generated AppLocalizations is Flutter, so the site cannot call it and
// looks its strings up by key at runtime instead. Naming the keys here is what
// stops the two sides disagreeing about them: the app resolves the same names
// as getters, and test/l10n/liturgical_keys_test.dart holds both to the ARB.

import '../liturgics/fasting.dart';
import '../models/calendar.dart';

String fastAllowanceKey(FastAllowance allowance) => switch (allowance) {
  FastAllowance.strict => 'fastAllowanceStrict',
  FastAllowance.wineAndOil => 'fastAllowanceWineAndOil',
  FastAllowance.fish => 'fastAllowanceFish',
  FastAllowance.dairyEggsAndFish => 'fastAllowanceDairyEggsAndFish',
  FastAllowance.free => 'fastAllowanceFree',
};

String fastSeasonKey(FastSeason season) => switch (season) {
  FastSeason.cheesefare => 'fastSeasonCheesefare',
  FastSeason.greatLent => 'fastSeasonGreatLent',
  FastSeason.apostles => 'fastSeasonApostles',
  FastSeason.dormition => 'fastSeasonDormition',
  FastSeason.nativity => 'fastSeasonNativity',
};

String dayMarkKey(DayMark mark) => switch (mark) {
  DayMark.majorFeast => 'markMajorFeast',
  DayMark.wineAndOil => 'markWineAndOil',
  DayMark.fish => 'markFish',
  DayMark.dairy => 'markDairy',
};

/// The tones are keyed by number, 1 to 8.
String toneKey(int tone) => 'tone$tone';
