import 'markup.dart';

export 'markup.dart';

/// Aliases so prayer code reads in prayer terms. A note is a rubric: an
/// instruction, not words to be said.
typedef PrayerSet = MarkupDocument;
typedef PrayerBlock = MarkupBlock;
typedef PrayerHeading = MarkupHeading;
typedef PrayerRubric = MarkupNote;
typedef PrayerText = MarkupText;
typedef PrayerDivider = MarkupDivider;
typedef PrayerList = MarkupList;

/// Each group must stay contiguous in [PrayerOccasion], or a list emits its
/// heading twice.
enum PrayerGroup { daily, liturgy }

/// An occasion the app offers a rule for. Declaration order is display order.
///
/// The second value is the notification id, stated rather than taken from
/// [index]. An id is fixed once assigned and a retired one is never reused, so
/// the enum can be reordered or pruned; derived from the index, a phone held a
/// scheduled id that came to mean a different rule and fired forever. Ids stay
/// below [FastingReminder.idBase].
enum PrayerOccasion {
  morning('morning', 0, PrayerGroup.daily),
  midday('midday', 1, PrayerGroup.daily),
  night('night', 2, PrayerGroup.daily),
  // 3, 4 and 5 were Small Compline and the two mealtime rules. Retired, not
  // reused.
  beforeCommunion('before_communion', 6, PrayerGroup.liturgy),
  afterCommunion('after_communion', 7, PrayerGroup.liturgy);

  const PrayerOccasion(this.slug, this.notificationId, this.group);

  final String slug;

  final int notificationId;

  final PrayerGroup group;

  String assetPath(String language) => 'res/prayers/${slug}_$language.md';

  static final Map<String, PrayerOccasion> _bySlug = {
    for (final occasion in values) occasion.slug: occasion,
  };

  /// Whether a group heading belongs above this occasion.
  bool get startsGroup => index == 0 || values[index - 1].group != group;

  /// For reading a slug back out of somewhere it was stored: a notification
  /// payload written days earlier, possibly by an older build.
  static PrayerOccasion? bySlug(String slug) => _bySlug[slug];

  /// The rule the hour of [time] belongs to, or null in the gaps.
  ///
  /// The app's windows, not the user's. A reminder is the moment someone asked
  /// to be nudged at, and setting the evening one for 21:00 does not make 21:00
  /// the evening. The afternoon and the small hours belong to no rule.
  static PrayerOccasion? forTime(DateTime time) => switch (time.hour) {
    >= 6 && < 12 => morning,
    >= 12 && < 15 => midday,
    >= 18 && < 22 => night,
    _ => null,
  };
}
