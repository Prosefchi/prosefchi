import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../l10n/liturgical_labels.dart';
import '../liturgics/fasting.dart';
import '../liturgics/octoechos.dart';
import '../liturgics/paschalion.dart';
import '../models/calendar.dart';
import '../services/calendar_repository.dart';
import '../services/prayer_repository.dart';
import '../services/settings_controller.dart';
import 'current_prayer_button.dart';
import 'settings_screen.dart';

/// The main screen: who is commemorated today, and the appointed readings.
///
/// Draws from the stored calendar and refreshes behind it, so opening the app
/// never waits on the network. Past the end of the feed it falls back to what
/// the Paschalion computes from nothing but a date.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.repository, this.prayers, this.date});

  final CalendarRepository? repository;

  final PrayerRepository? prayers;

  /// Carries a time as well as a date, and doubles as the clock the
  /// current-prayer button reads, so fixing it fixes the hour too.
  final DateTime? date;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late final CalendarRepository _repository =
      widget.repository ?? sharedCalendarRepository;

  late final DateTime _date = widget.date ?? DateTime.now();

  String? _language;
  CalendarStyle _style = CalendarStyle.gregorian;
  CalendarDay? _day;
  bool _loading = true;
  bool _haveCalendar = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The locale is not available in initState. Reload only when the language
    // actually changes, since this fires for unrelated dependency changes too.
    final language = languageFor(Localizations.localeOf(context));
    final style =
        SettingsScope.maybeOf(context)?.calendarStyle ??
        CalendarStyle.gregorian;
    if (language == _language && style == _style) return;
    _language = language;
    _style = style;
    _load(language);
  }

  /// Reads the stored calendar, then refreshes behind it.
  Future<void> _load(String language) async {
    setState(() => _loading = true);
    await _apply(language);

    if (_day == null) {
      // Nothing to show yet, so wait for the first fetch rather than flashing
      // "not downloaded" and replacing it a moment later. This is the only
      // path where the user waits on the network.
      await _repository.refresh(language, style: _style);
      await _apply(language);
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Something is already on screen, so a failure here is silent.
    setState(() => _loading = false);
    if (await _repository.refresh(language, style: _style) && mounted) {
      await _apply(language);
      if (mounted) setState(() {});
    }
  }

  Future<void> _apply(String language) async {
    final calendar = await _repository.load(language, style: _style);
    if (!mounted) return;
    _haveCalendar = calendar != null;
    _day = calendar?.forDate(_date);
  }

  Future<void> _retry() async {
    if (_language case final language?) await _load(language);
  }

  /// The fasting rule from the Paschalion, for days upstream does not cover.
  ///
  /// Never null: every date resolves to something, so a day with no fast says
  /// so rather than leaving the slot empty. An empty slot is ambiguous between
  /// there being no fast and our not knowing, and those are not the same
  /// answer to give someone who opened the app to check.
  static String _computedFasting(
    AppLocalizations l10n,
    DateTime date,
    CalendarStyle style,
  ) {
    if (fastSeasonFor(date, style: style) case final season?) {
      return l10n.fastSeasonLabel(season);
    }
    return isFastDay(date, style: style) ? l10n.fastDay : l10n.noFast;
  }

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
              // The civil date stays the headline: it is what the phone and
              // everyone around the reader use. The weekday is written once,
              // against it, because a converted date has no usable one.
              secondaryDate: _style == CalendarStyle.gregorian
                  ? null
                  : l10n.julianDate(
                      DateFormat.yMMMMd(
                        _language ?? 'en',
                      ).format(_style.dateOf(_date)),
                    ),
              title: day?.title,
              marks: day?.marks ?? const [],
              // Upstream states the rule on most days it covers and is
              // authoritative there. Past the end of the feed, and on the
              // handful of days it puts something else in that slot, the
              // computed season stands in.
              fasting:
                  l10n.fastAllowanceLabel(day?.fastAllowance) ??
                  _computedFasting(l10n, _date, _style),
            ),
            // All computed, so this appears in every state and the no-data
            // screen keeps the shape of the ordinary one.
            _LiturgicalStrip(
              date: _date,
              tone: day?.tone ?? toneFor(_date),
              eothinon: day?.eothinon ?? eothinonFor(_date),
            ),
            // Absent outside the hours a rule belongs to, so nothing here
            // reserves space for it.
            CurrentPrayerButton(
              clock: () => widget.date ?? DateTime.now(),
              repository: widget.prayers,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (day != null) ...[
              if (day.saints.length > 1)
                _CommemorationsCard(saints: day.saints),
              if (day.oldTestament case final reading?)
                _ReadingCard(
                  heading: l10n.oldTestamentReading,
                  reading: reading,
                ),
              if (day.epistle case final epistle?)
                _ReadingCard(heading: l10n.epistleReading, reading: epistle),
              if (day.gospel case final gospel?)
                _ReadingCard(heading: l10n.gospelReading, reading: gospel),
              // A separate reading from the Gospel, not a variant of it.
              if (day.matinsGospel case final reading?)
                _ReadingCard(
                  heading: l10n.matinsGospelReading,
                  reading: reading,
                ),
            ] else
              // Resolved here, like the header's: three states, of which
              // only two are worth a retry.
              _EmptyDayCard(
                message: switch (_style.isPublishedFor(_language ?? 'en')) {
                  false => l10n.calendarNotPublished,
                  true when _haveCalendar => l10n.noEntryForDay,
                  true => l10n.calendarNotDownloaded,
                },
                // A button that cannot succeed reads as the app being broken
                // rather than as a state it was designed for.
                onRetry: _style.isPublishedFor(_language ?? 'en')
                    ? _retry
                    : null,
              ),
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
    required this.secondaryDate,
    required this.title,
    required this.marks,
    required this.fasting,
  });

  final DateTime date;
  final String locale;

  /// The same day on another calendar, where the reader keeps one. Resolved by
  /// the caller, like [fasting] beside it — this draws words, it does not
  /// decide them.
  final String? secondaryDate;
  final String? title;
  final List<DayMark> marks;

  /// The fasting rule in words, where upstream gives one.
  final String? fasting;

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
            if (secondaryDate case final line?)
              Text(
                line,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer.withValues(
                    alpha: 0.6,
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
            if (_pills(l10n) case final pills when pills.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: pills),
            ],
          ],
        ),
      ),
    );
  }

  /// The rule in words wins and the fasting markers are dropped, or the day
  /// reads as labelled twice. Across the whole feed a marker never appears
  /// without a rule beside it, so nothing is lost.
  List<Widget> _pills(AppLocalizations l10n) => [
    for (final mark in marks)
      if (fasting == null || mark == DayMark.majorFeast)
        _Pill(
          leading: Text(mark.symbol, style: const TextStyle(fontSize: 13)),
          label: l10n.dayMarkLabel(mark),
        ),
    if (fasting case final rule?)
      _Pill(
        leading: const Icon(Icons.restaurant_outlined, size: 13),
        label: rule,
      ),
  ];
}

class _Pill extends StatelessWidget {
  const _Pill({required this.leading, required this.label});

  final Widget leading;
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
      // A Wrap gives its children unbounded width, so without Flexible a long
      // fasting rule runs off the edge instead of wrapping inside the pill.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: theme.textTheme.labelMedium)),
        ],
      ),
    );
  }
}

/// Where the day sits in the year. All three need no data, so this is what the
/// screen can always say. The tone is absent through Bright Week.
class _LiturgicalStrip extends StatelessWidget {
  const _LiturgicalStrip({
    required this.date,
    required this.tone,
    required this.eothinon,
  });

  final DateTime date;
  final int? tone;
  final int? eothinon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offset = daysBetween(orthodoxPascha(date.year), date);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          _Fact(
            icon: Icons.brightness_2_outlined,
            label: offset >= 0
                ? l10n.daysAfterPascha(offset)
                : l10n.daysUntilPascha(-offset),
          ),
          if (tone case final tone?)
            _Fact(icon: Icons.music_note_outlined, label: l10n.toneLabel(tone)),
          if (eothinon case final eothinon?)
            _Fact(
              icon: Icons.auto_stories_outlined,
              label: l10n.eothinon(eothinon),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Flexible for the same reason as the pill above.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ),
      ],
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
                // Fixed strings, but wider than a narrow phone at the large
                // text size, so they have to be allowed to wrap.
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
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

/// A reading, with its several hundred words folded away behind the citation,
/// which is what people scan for.
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
        // ExpansionTile's divider draws a hairline at the card edge, which
        // reads as a rendering fault rather than as a border.
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

/// Shown when the calendar has no entry for the day. The feed ends on a fixed
/// date and has lapsed for a year before, so this is a state to sit in.
class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard({required this.message, required this.onRetry});

  final String message;

  /// Null where retrying cannot help.
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, onRetry == null ? 20 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  // A struck-through cloud says "offline": true of the two
                  // retryable states, a lie about the third.
                  onRetry == null
                      ? Icons.info_outline
                      : Icons.cloud_off_outlined,
                  size: 16,
                  color: theme.hintColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
              ],
            ),
            if (onRetry case final retry?)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: retry,
                  child: Text(AppLocalizations.of(context).retry),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
