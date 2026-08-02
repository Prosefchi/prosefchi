import 'package:flutter/material.dart';

import '../models/prayer.dart';

/// Here rather than in the l10n extension, which is about wording: an icon does
/// not change with the language.
IconData occasionIcon(PrayerOccasion occasion) => switch (occasion) {
  PrayerOccasion.morning => Icons.wb_twilight,
  PrayerOccasion.midday => Icons.light_mode_outlined,
  PrayerOccasion.night => Icons.nights_stay_outlined,
  PrayerOccasion.beforeCommunion => Icons.church_outlined,
  PrayerOccasion.afterCommunion => Icons.church,
};

/// A heading over a run of occasions belonging to one group. Shared by the
/// prayers list and the reminders list so the two cannot disagree.
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
