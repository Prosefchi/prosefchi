import 'markup.dart';

export 'markup.dart';

/// A prayer rule is an authored document; the format is shared with the
/// welcome pages, so the parser lives in markup.dart.
///
/// These aliases keep prayer code reading in prayer terms. `PrayerRubric` in
/// particular is worth preserving: in a prayer a note is a rubric, an
/// instruction rather than words to be said.
typedef PrayerSet = MarkupDocument;
typedef PrayerBlock = MarkupBlock;
typedef PrayerHeading = MarkupHeading;
typedef PrayerRubric = MarkupNote;
typedef PrayerText = MarkupText;

/// What kind of occasion a prayer rule belongs to.
///
/// Declaration order is display order, and [PrayerOccasion] is already ordered
/// so each group is contiguous.
enum PrayerGroup {
  /// Tied to the hours of the day, and to meals, which come round daily too.
  daily,

  /// Tied to the Divine Liturgy rather than to the clock. Someone who receives
  /// monthly wants these on a different footing from a morning rule.
  liturgy,
}

/// An occasion the app offers a rule for.
///
/// Not "time of day": meals and Communion are occasions rather than hours, and
/// declaration order is the order they are listed in, so daily rules come
/// first.
///
/// [slug] is stated rather than derived from [name], so the asset filenames
/// stay snake_case while the Dart identifiers stay camelCase.
enum PrayerOccasion {
  morning('morning', PrayerGroup.daily),
  midday('midday', PrayerGroup.daily),
  night('night', PrayerGroup.daily),
  compline('compline', PrayerGroup.daily),
  beforeMeal('before_meal', PrayerGroup.daily),
  afterMeal('after_meal', PrayerGroup.daily),
  beforeCommunion('before_communion', PrayerGroup.liturgy),
  afterCommunion('after_communion', PrayerGroup.liturgy);

  const PrayerOccasion(this.slug, this.group);

  final String slug;

  final PrayerGroup group;

  String assetPath(String language) => 'res/prayers/${slug}_$language.md';
}
