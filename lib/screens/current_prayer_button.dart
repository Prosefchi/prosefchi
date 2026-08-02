import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/occasion_labels.dart';
import '../models/prayer.dart';
import '../services/calendar_repository.dart' show languageFor;
import '../services/prayer_repository.dart';
import 'occasion_ui.dart';
import 'prayers_screen.dart';

/// Opens the rule the hour belongs to, as the day screen's one obvious action.
///
/// Takes itself off the page outside those hours rather than reaching for the
/// nearest rule, and likewise for a rule whose text is still awaited: a hero
/// button onto an empty page promises more than a greyed-out row does.
class CurrentPrayerButton extends StatefulWidget {
  const CurrentPrayerButton({
    super.key,
    this.clock = DateTime.now,
    this.repository,
  });

  /// Read again on every resume rather than captured, so a test can fix the
  /// hour it checks and then move it.
  final DateTime Function() clock;

  final PrayerRepository? repository;

  @override
  State<CurrentPrayerButton> createState() => _CurrentPrayerButtonState();
}

class _CurrentPrayerButtonState extends State<CurrentPrayerButton> {
  late final PrayerRepository _repository =
      widget.repository ?? sharedPrayerRepository;

  late final AppLifecycleListener _lifecycle;

  PrayerOccasion? _occasion;
  PrayerSet? _set;
  String? _language;

  @override
  void initState() {
    super.initState();
    _occasion = PrayerOccasion.forTime(widget.clock());
    _lifecycle = AppLifecycleListener(onResume: _reconsider);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The locale is not available in initState. Reload only when the language
    // actually changes, since this fires for unrelated dependency changes too.
    final language = languageFor(Localizations.localeOf(context));
    if (language == _language) return;
    _language = language;
    _load();
  }

  /// The day screen is kept alive in an [IndexedStack], so its build runs about
  /// once per launch: without this, a phone opened at breakfast and again after
  /// lunch would still be offering the morning rule.
  ///
  /// Only on resume, no timer. An hour turning over while someone is looking at
  /// the page is much the rarer case.
  void _reconsider() {
    final occasion = PrayerOccasion.forTime(widget.clock());
    if (occasion == _occasion) return;
    setState(() {
      _occasion = occasion;
      _set = null;
    });
    _load();
  }

  Future<void> _load() async {
    final occasion = _occasion;
    final language = _language;
    if (occasion == null || language == null) return;

    final set = await _repository.load(occasion, language);
    // The hour can have turned over while this was in flight, and the rule it
    // turned to has a read of its own on the way.
    if (!mounted || occasion != _occasion) return;
    setState(() => _set = set);
  }

  @override
  Widget build(BuildContext context) {
    final occasion = _occasion;
    final set = _set;
    if (occasion == null || set == null || !set.hasContent) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final foreground = theme.colorScheme.onPrimary;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FilledButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => PrayerScreen(set: set))),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        ),
        child: Row(
          children: [
            Icon(occasionIcon(occasion), size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Supplies the verb: on its own, "Morning" beside a date
                  // reads as a label rather than as somewhere to go.
                  Text(
                    l10n.prayNow,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground.withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    l10n.occasionLabel(occasion),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
