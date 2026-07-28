import '../models/prayer.dart';
import 'app_localizations.dart';

/// The display name of a prayer occasion.
///
/// One definition, used by the prayers list, the reminders screen and the text
/// baked into a scheduled notification. Three copies of this switch would be
/// three chances for a notification to call a rule something the list does not.
extension PrayerOccasionLabels on AppLocalizations {
  String groupLabel(PrayerGroup group) => switch (group) {
    PrayerGroup.daily => prayerGroupDaily,
    PrayerGroup.liturgy => prayerGroupLiturgy,
  };

  String occasionLabel(PrayerOccasion occasion) => switch (occasion) {
    PrayerOccasion.morning => prayerMorning,
    PrayerOccasion.midday => prayerMidday,
    PrayerOccasion.night => prayerNight,
    PrayerOccasion.beforeCommunion => prayerBeforeCommunion,
    PrayerOccasion.afterCommunion => prayerAfterCommunion,
  };
}
