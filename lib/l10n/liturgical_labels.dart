import '../liturgics/fasting.dart';
import '../models/calendar.dart';
import 'app_localizations.dart';

/// Display names for the computed and published liturgical values.
extension LiturgicalLabels on AppLocalizations {
  /// The tone by its traditional name rather than its number.
  ///
  /// Greek names the plagal tones as plagal and the seventh as grave, so
  /// rendering "Ήχος 5" would read as wrong to anyone who knows the Octoechos.
  /// English follows the same shape for consistency.
  String toneLabel(int tone) => switch (tone) {
    1 => tone1,
    2 => tone2,
    3 => tone3,
    4 => tone4,
    5 => tone5,
    6 => tone6,
    7 => tone7,
    _ => tone8,
  };

  String fastSeasonLabel(FastSeason season) => switch (season) {
    FastSeason.cheesefare => fastSeasonCheesefare,
    FastSeason.greatLent => fastSeasonGreatLent,
    FastSeason.apostles => fastSeasonApostles,
    FastSeason.dormition => fastSeasonDormition,
    FastSeason.nativity => fastSeasonNativity,
  };

  /// The published fasting rule in words.
  ///
  /// The wording is upstream's own, so what the app draws is unchanged from
  /// when the calendar carried the sentence itself. The difference is that it
  /// is now the app saying it, which is what lets a day parsed out of an
  /// English-only source be read in Greek.
  String fastAllowanceLabel(FastAllowance allowance) => switch (allowance) {
    FastAllowance.strict => fastAllowanceStrict,
    FastAllowance.wineAndOil => fastAllowanceWineAndOil,
    FastAllowance.fish => fastAllowanceFish,
    FastAllowance.dairyEggsAndFish => fastAllowanceDairyEggsAndFish,
    FastAllowance.free => fastAllowanceFree,
  };
}
