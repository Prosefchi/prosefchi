import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/occasion_labels.dart';
import '../models/prayer.dart';
import 'markup_paragraph.dart';
import '../services/calendar_repository.dart' show languageFor;
import '../services/prayer_repository.dart';
import 'occasion_ui.dart';
import 'settings_screen.dart';

/// Lists the rules and opens one to read.
class PrayersScreen extends StatefulWidget {
  const PrayersScreen({super.key, this.repository});

  /// Injectable so tests need no real asset bundle.
  final PrayerRepository? repository;

  @override
  State<PrayersScreen> createState() => _PrayersScreenState();
}

class _PrayersScreenState extends State<PrayersScreen> {
  late final PrayerRepository _repository =
      widget.repository ?? sharedPrayerRepository;

  String? _language;
  Map<PrayerOccasion, PrayerSet?> _sets = {};
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = languageFor(Localizations.localeOf(context));
    if (language == _language) return;
    _language = language;
    _load(language);
  }

  Future<void> _load(String language) async {
    setState(() => _loading = true);
    // Eight independent asset reads. Serialized they cost eight round trips,
    // and HomeShell's IndexedStack means this runs at launch rather than when
    // the tab is first opened.
    final sets = await Future.wait([
      for (final occasion in PrayerOccasion.values)
        _repository.load(occasion, language),
    ]);
    final loaded = {
      for (final (index, occasion) in PrayerOccasion.values.indexed)
        occasion: sets[index],
    };
    if (!mounted) return;
    setState(() {
      _sets = loaded;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.prayers),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settings,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final occasion in PrayerOccasion.values) ...[
                  if (startsGroup(occasion))
                    GroupHeading(
                      occasion: occasion,
                      label: l10n.groupLabel(occasion.group),
                    ),
                  _PrayerTile(
                    icon: occasionIcon(occasion),
                    label: l10n.occasionLabel(occasion),
                    set: _sets[occasion],
                    unavailable: l10n.prayerNotAvailable,
                  ),
                ],
              ],
            ),
    );
  }
}

class _PrayerTile extends StatelessWidget {
  const _PrayerTile({
    required this.icon,
    required this.label,
    required this.set,
    required this.unavailable,
  });

  final IconData icon;
  final String label;
  final PrayerSet? set;
  final String unavailable;

  @override
  Widget build(BuildContext context) {
    // Unavailable means there is nothing to pray, not that the rule is
    // unfinished: the morning rule holds the Trisagion alongside a marked gap,
    // and hiding it because of the gap would withhold text that is ready.
    final ready = set != null && set!.hasContent;

    return ListTile(
      // ListTile greys the leading icon along with the text when disabled, so
      // an unavailable rule reads as one thing rather than a bright icon
      // beside faded words.
      leading: Icon(icon),
      title: Text(label),
      subtitle: ready ? null : Text(unavailable),
      enabled: ready,
      trailing: ready ? const Icon(Icons.chevron_right) : null,
      onTap: ready
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => PrayerScreen(set: set!)),
            )
          : null,
    );
  }
}

/// Renders one rule.
class PrayerScreen extends StatelessWidget {
  const PrayerScreen({super.key, required this.set});

  final PrayerSet set;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(set.title)),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
        itemCount: set.blocks.length,
        itemBuilder: (context, index) => switch (set.blocks[index]) {
          PrayerHeading(:final text) => Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 10),
            child: Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          // Rubrics are instructions, not words to be said. Styling them
          // apart is the whole reason for the distinction.
          PrayerRubric(:final spans) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MarkupParagraph(
              spans,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.hintColor,
              ),
            ),
          ),
          PrayerText(:final spans) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: MarkupParagraph(
              spans,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
          ),
          PrayerDivider() => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
        },
      ),
    );
  }
}
