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

/// An occasion the app offers a rule for.
///
/// Not "time of day": meals and Communion are occasions rather than hours, and
/// declaration order is the order they are listed in, so daily rules come
/// first.
///
/// [slug] is stated rather than derived from [name], so the asset filenames
/// stay snake_case while the Dart identifiers stay camelCase.
enum PrayerOccasion {
  morning('morning'),
  midday('midday'),
  night('night'),
  compline('compline'),
  beforeMeal('before_meal'),
  afterMeal('after_meal'),
  beforeCommunion('before_communion'),
  afterCommunion('after_communion');

  const PrayerOccasion(this.slug);

  final String slug;

  String assetPath(String language) => 'res/prayers/${slug}_$language.md';
}
