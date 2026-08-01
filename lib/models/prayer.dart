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
typedef PrayerDivider = MarkupDivider;
typedef PrayerList = MarkupList;

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
/// The second value is the notification id, and it is stated rather than taken
/// from the declaration order on purpose. Deriving it from `index` made the
/// enum append-only forever: removing or reordering an entry shifted the ids
/// of everything after it, and a phone with a reminder already scheduled then
/// held an id that meant a different rule — impossible to cancel or update, so
/// it would fire forever. Stating it decouples the two, and the only rule left
/// is the easy one to keep.
///
/// **An id is fixed once assigned, and a retired one is never reused.** A new
/// occasion takes the next unused number, wherever it is declared. 3, 4 and 5
/// belonged to Small Compline and the two mealtime rules and are spent, even
/// though nothing had shipped when they went — the point of a rule like this
/// is that it does not depend on remembering which exemptions were taken.
///
/// Ids stay well below [FastingReminder.idBase], which is where the fasting
/// block starts.
enum PrayerOccasion {
  morning('morning', 0, PrayerGroup.daily),
  midday('midday', 1, PrayerGroup.daily),
  night('night', 2, PrayerGroup.daily),
  // 3, 4 and 5 were Small Compline and the two mealtime rules. Retired, not
  // reused: these two keep the ids they were given rather than sliding down,
  // which is the whole reason the id is stated rather than counted.
  beforeCommunion('before_communion', 6, PrayerGroup.liturgy),
  afterCommunion('after_communion', 7, PrayerGroup.liturgy);

  const PrayerOccasion(this.slug, this.notificationId, this.group);

  final String slug;

  /// What a scheduled notification for this occasion is posted and cancelled
  /// by. See the note above the enum: fixed per occasion, never reused.
  final int notificationId;

  final PrayerGroup group;

  String assetPath(String language) => 'res/prayers/${slug}_$language.md';

  static final Map<String, PrayerOccasion> _bySlug = {
    for (final occasion in values) occasion.slug: occasion,
  };

  /// Whether this occasion opens a new group and so wants a heading above it.
  ///
  /// Leans on the declaration order keeping each group contiguous, which
  /// `test/models/reminder_test.dart` pins. Here rather than beside the
  /// widgets so the prayers list, the reminders list and the website cannot
  /// disagree about where the breaks fall.
  bool get startsGroup => index == 0 || values[index - 1].group != group;

  /// The occasion with this [slug], or null if none has it.
  ///
  /// For reading a slug back out of somewhere it was stored — a notification
  /// payload written days earlier, possibly by an older build.
  static PrayerOccasion? bySlug(String slug) => _bySlug[slug];

  /// The rule the hour of [time] belongs to, or null where none does.
  ///
  ///     06:00–12:00  morning
  ///     12:00–15:00  midday
  ///     18:00–22:00  night
  ///
  /// Fixed here rather than read from the reminders, which answer a different
  /// question. A reminder is the moment someone asked to be nudged at, and
  /// setting the evening one for 21:00 does not make 21:00 the evening; this is
  /// which rule the hour itself belongs to, so it is the app's to decide.
  ///
  /// The windows are half-open, so a boundary opens one rather than closing
  /// one: noon is the midday rule, not the last minute of the morning.
  ///
  /// The gaps between them are deliberate and this says so by returning null:
  /// the afternoon and the small hours belong to no rule, and offering the
  /// morning one at four in the afternoon would be worse than offering nothing.
  static PrayerOccasion? forTime(DateTime time) => switch (time.hour) {
    >= 6 && < 12 => morning,
    >= 12 && < 15 => midday,
    >= 18 && < 22 => night,
    _ => null,
  };
}
