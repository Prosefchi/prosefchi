import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../liturgics/paschalion.dart';
import '../models/calendar.dart';
import '../services/calendar_repository.dart';
import 'settings_screen.dart';

/// The main screen: who is commemorated today, and the appointed readings.
///
/// Draws from the stored calendar immediately and refreshes in the background,
/// so opening the app never waits on the network. When there is no entry — a
/// first launch, or a date past the end of the published feed — it falls back
/// to what the Paschalion can compute without any data at all.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.repository, this.date});

  /// Injectable so tests need neither a network nor a real filesystem.
  final CalendarRepository? repository;

  /// Injectable so tests are not tied to the day they run on.
  final DateTime? date;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late final CalendarRepository _repository =
      widget.repository ?? CalendarRepository();

  late final DateTime _date = widget.date ?? DateTime.now();

  String? _language;
  CalendarDay? _day;
  bool _loading = true;
  bool _haveCalendar = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The locale is not available in initState. Reload only when the language
    // actually changes, since this fires for unrelated dependency changes too.
    final language = _languageFor(Localizations.localeOf(context));
    if (language == _language) return;
    _language = language;
    _load(language);
  }

  @override
  void dispose() {
    if (widget.repository == null) _repository.dispose();
    super.dispose();
  }

  /// Reads the stored calendar, then refreshes behind it.
  Future<void> _load(String language) async {
    setState(() => _loading = true);
    await _apply(language);

    if (_day == null) {
      // Nothing to show yet, so wait for the first fetch rather than flashing
      // "not downloaded" and replacing it a moment later. This is the only
      // path where the user waits on the network.
      await _repository.refresh(language);
      await _apply(language);
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Something is already on screen, so refresh behind it. A failure here is
    // silent by design: whatever was stored stays put.
    setState(() => _loading = false);
    if (await _repository.refresh(language) && mounted) {
      await _apply(language);
      if (mounted) setState(() {});
    }
  }

  Future<void> _apply(String language) async {
    final calendar = await _repository.load(language);
    if (!mounted) return;
    _haveCalendar = calendar != null;
    _day = calendar?.forDate(_date);
  }

  Future<void> _retry() async {
    if (_language case final language?) await _load(language);
  }

  static String _languageFor(Locale locale) =>
      supportedLanguages.contains(locale.languageCode)
      ? locale.languageCode
      : supportedLanguages.first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final day = _day;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.today),
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
      body: RefreshIndicator(
        onRefresh: _retry,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _DayHeader(
              date: _date,
              locale: _language ?? 'en',
              title: day?.title,
              marks: day?.marks ?? const [],
            ),
            // Computed, so it appears in every state. It also means the
            // no-data screen keeps the same shape as the ordinary one rather
            // than becoming a jarringly different page.
            _PaschaLine(date: _date),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (day != null) ...[
              if (day.saints.length > 1)
                _CommemorationsCard(saints: day.saints),
              if (day.epistle case final epistle?)
                _ReadingCard(heading: l10n.epistleReading, reading: epistle),
              if (day.gospel case final gospel?)
                _ReadingCard(heading: l10n.gospelReading, reading: gospel),
            ] else
              _EmptyDayCard(haveCalendar: _haveCalendar, onRetry: _retry),
          ],
        ),
      ),
    );
  }
}

/// The date and the day's commemoration, as the anchor of the page.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.locale,
    required this.title,
    required this.marks,
  });

  final DateTime date;
  final String locale;
  final String? title;
  final List<DayMark> marks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat.yMMMMEEEEd(locale).format(date),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(
                  alpha: 0.75,
                ),
              ),
            ),
            if (title case final headline? when headline.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                headline,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  height: 1.25,
                ),
              ),
            ],
            if (marks.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mark in marks)
                    _MarkChip(mark: mark, label: _markLabel(l10n, mark)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _markLabel(AppLocalizations l10n, DayMark mark) =>
      switch (mark) {
        DayMark.majorFeast => l10n.markMajorFeast,
        DayMark.wineAndOil => l10n.markWineAndOil,
        DayMark.fish => l10n.markFish,
        DayMark.dairy => l10n.markDairy,
      };
}

class _MarkChip extends StatelessWidget {
  const _MarkChip({required this.mark, required this.label});

  final DayMark mark;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mark.symbol, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// How far the day sits from Pascha.
///
/// Needs no data at all, so it is the one thing the screen can always say,
/// including after the published feed lapses.
class _PaschaLine extends StatelessWidget {
  const _PaschaLine({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final offset = daysBetween(orthodoxPascha(date.year), date);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
      child: Row(
        children: [
          Icon(
            Icons.brightness_2_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(
            offset >= 0
                ? l10n.daysAfterPascha(offset)
                : l10n.daysUntilPascha(-offset),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}

/// A card with a small labelled header, used for each section of the page.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CommemorationsCard extends StatelessWidget {
  const _CommemorationsCard({required this.saints});

  final List<String> saints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SectionCard(
      icon: Icons.people_outline,
      label: AppLocalizations.of(context).commemorations,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final saint in saints)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      saint,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A reading, with its text folded away behind the citation.
///
/// The passages run to several hundred words each, and two of them expanded
/// are what turned this page into a slab. The citation is what people scan
/// for; the text is one tap away.
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.heading, required this.reading});

  final String heading;
  final Reading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTile's default divider draws a hairline right at the card
        // edge, which reads as a rendering fault rather than as a border.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(
            Icons.menu_book_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            heading,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          subtitle: Text(reading.reference, style: theme.textTheme.titleSmall),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reading.text case final text?)
              Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the calendar has no entry for the day.
///
/// The published feed ends on a fixed date and upstream has let it lapse for a
/// year before, so this is a state the app will genuinely sit in rather than a
/// first-launch nicety.
class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard({required this.haveCalendar, required this.onRetry});

  final bool haveCalendar;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: theme.hintColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    haveCalendar
                        ? l10n.noEntryForDay
                        : l10n.calendarNotDownloaded,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: onRetry, child: Text(l10n.retry)),
            ),
          ],
        ),
      ),
    );
  }
}
