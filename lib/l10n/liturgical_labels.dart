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

  /// The published fasting rule in words, or null where none was published.
  ///
  /// Nullable in and out so callers keep the `??` shape the rest of the day's
  /// resolution uses — every one of them falls back to the computed layer.
  String? fastAllowanceLabel(FastAllowance? allowance) => switch (allowance) {
    FastAllowance.strict => fastAllowanceStrict,
    FastAllowance.wineAndOil => fastAllowanceWineAndOil,
    FastAllowance.fish => fastAllowanceFish,
    FastAllowance.dairyEggsAndFish => fastAllowanceDairyEggsAndFish,
    FastAllowance.free => fastAllowanceFree,
    null => null,
  };
}
