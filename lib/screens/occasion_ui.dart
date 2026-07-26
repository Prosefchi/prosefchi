import 'package:flutter/material.dart';

import '../models/prayer.dart';

/// An icon for each occasion.
///
/// Kept beside the group heading rather than in the l10n extension, which is
/// about wording: an icon does not change with the language.
IconData occasionIcon(PrayerOccasion occasion) => switch (occasion) {
  PrayerOccasion.morning => Icons.wb_twilight,
  PrayerOccasion.midday => Icons.light_mode_outlined,
  PrayerOccasion.night => Icons.nights_stay_outlined,
  PrayerOccasion.compline => Icons.bedtime_outlined,
  PrayerOccasion.beforeMeal => Icons.restaurant_outlined,
  PrayerOccasion.afterMeal => Icons.restaurant_menu_outlined,
  PrayerOccasion.beforeCommunion => Icons.church_outlined,
  PrayerOccasion.afterCommunion => Icons.church,
};

/// Whether [occasion] opens a new group and so wants a heading above it.
///
/// Leans on [PrayerOccasion] being ordered so each group is contiguous, which
/// `test/models/reminder_test.dart` pins. Lives here rather than in each list
/// so the two screens cannot disagree about where the breaks fall.
bool startsGroup(PrayerOccasion occasion) =>
    occasion.index == 0 ||
    PrayerOccasion.values[occasion.index - 1].group != occasion.group;

/// A heading over a run of occasions belonging to one group.
///
/// Shared by the prayers list and the reminders list so the two present the
/// same structure. [PrayerOccasion] is ordered so each group is contiguous,
/// and callers emit one of these wherever the group changes.
class GroupHeading extends StatelessWidget {
  const GroupHeading({super.key, required this.occasion, required this.label});

  final PrayerOccasion occasion;
  final String label;

  /// The first heading needs no rule above it; the page edge already separates
  /// it from what came before.
  bool get first => occasion.index == 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!first) const Divider(height: 24),
        Padding(
          padding: EdgeInsets.fromLTRB(16, first ? 16 : 0, 16, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
