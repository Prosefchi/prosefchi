import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/occasion_labels.dart';
import '../models/prayer.dart';
import '../models/text_size.dart';
import 'markup_list.dart';
import 'markup_paragraph.dart';
import 'reading_scrollbar.dart';
import '../services/calendar_repository.dart' show languageFor;
import '../services/prayer_repository.dart';
import '../services/settings_controller.dart';
import 'occasion_ui.dart';
import 'settings_screen.dart';

/// Lists the rules and opens one to read.
class PrayersScreen extends StatefulWidget {
  const PrayersScreen({super.key, this.repository});

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
    // Independent asset reads, and HomeShell's IndexedStack runs this at
    // launch rather than when the tab is first opened.
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
                  if (occasion.startsGroup)
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
    // Nothing to pray, not an unfinished rule: a rule can hold real text and a
    // marked gap, and hiding it for the gap withholds text that is ready.
    final ready = set != null && set!.hasContent;

    return ListTile(
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
class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key, required this.set});

  final PrayerSet set;

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  /// The only reason this screen holds state: a draggable bar has to drive the
  /// scrollable it measures, and a controller has to be disposed.
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// [theme] is passed rather than re-read: the longest rule calls this 286
  /// times.
  Widget _block(ThemeData theme, PrayerBlock block) => switch (block) {
    PrayerHeading(:final text) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    ),
    // Instructions, not words to be said.
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
    PrayerList() => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: MarkupItems(
        block,
        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
      ),
    ),
    PrayerDivider() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Divider(),
    ),
    // HTML passthrough is not supported in the app.
    MarkupHtmlBlock() => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final set = widget.set;

    // The passage and nothing else: not the app bar, and no other screen. A
    // rule is the one thing here anybody reads at length. Read leniently, so a
    // rule shown with no settings above it draws at the default.
    final media = MediaQuery.of(context);
    final size = SettingsScope.maybeOf(context)?.textSize ?? TextSize.small;

    return Scaffold(
      appBar: AppBar(title: Text(set.title)),
      // ReadingScrollbar rather than Scrollbar, so only the pill scrolls and
      // not the whole column it runs in.
      body: MediaQuery(
        data: media.copyWith(textScaler: size.over(media.textScaler)),
        child: ReadingScrollbar(
          controller: _controller,
          showProgress: true,
          // Laid out in full rather than lazily, so the scrollbar has a real
          // height to measure: a lazy viewport estimates the extent from what
          // it has built, and the thumb drawn from that changed size under the
          // finger. Costs three to five times the first frame, affordable only
          // because the longest rule is 286 blocks. Revisit past six hundred.
          child: SingleChildScrollView(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final block in set.blocks) _block(theme, block)],
            ),
          ),
        ),
      ),
    );
  }
}
