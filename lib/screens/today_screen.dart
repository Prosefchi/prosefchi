import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../l10n/liturgical_labels.dart';
import '../liturgics/fasting.dart';
import '../liturgics/julian.dart';
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
/// Draws from the stored calendar immediately and refreshes in the background,
/// so opening the app never waits on the network. When there is no entry — a
/// first launch, or a date past the end of the published feed — it falls back
/// to what the Paschalion can compute without any data at all.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.repository, this.prayers, this.date});

  /// Injectable so tests need neither a network nor a real filesystem.
  final CalendarRepository? repository;

  /// Injectable so a test of the current-prayer button needs no asset bundle.
  final PrayerRepository? prayers;

  /// Injectable so tests are not tied to the day they run on.
  ///
  /// It carries a time as well as a date, and doubles as the clock the
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

    // Something is already on screen, so refresh behind it. A failure here is
    // silent by design: whatever was stored stays put.
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

  /// The fasting rule worked out from the Paschalion, for days upstream does
  /// not cover. Names the season where there is one, since that says more than
  /// simply that the day fasts.
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
              style: _style,
              locale: _language ?? 'en',
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
            // All computed, so this appears in every state. It also means the
            // no-data screen keeps the same shape as the ordinary one rather
            // than becoming a jarringly different page.
            _LiturgicalStrip(
              date: _date,
              tone: day?.tone ?? toneFor(_date),
              eothinon: day?.eothinon ?? eothinonFor(_date),
            ),
            // Under everything the day *is* — its commemoration and where it
            // sits in the year — and above the readings, which is where doing
            // something about the day begins. Absent outside the hours a rule
            // belongs to, which is why nothing here reserves space for it.
            CurrentPrayerButton(
              // The live clock unless a date was injected, in which case its
              // time of day is the hour under test.
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
              // A separate reading from the Gospel, not a variant of it, so it
              // gets its own card rather than being folded in beside it.
              if (day.matinsGospel case final reading?)
                _ReadingCard(
                  heading: l10n.matinsGospelReading,
                  reading: reading,
                ),
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
    required this.style,
    required this.locale,
    required this.title,
    required this.marks,
    required this.fasting,
  });

  final DateTime date;
  final CalendarStyle style;
  final String locale;
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
            // The civil date stays the headline even on the old calendar: it
            // is the date the phone and everyone around the reader are using.
            // The Julian date sits under it, which is also why the weekday is
            // only written once — julianDateOf returns calendar fields rather
            // than an instant, and its weekday would be a fortnight out.
            if (style == CalendarStyle.julian)
              Text(
                l10n.julianDate(
                  DateFormat.yMMMMd(locale).format(julianDateOf(date)),
                ),
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

  /// The rank and fasting pills.
  ///
  /// The fasting rule in words wins and the fasting markers are dropped: they
  /// say the same thing less precisely, and showing both reads as the day
  /// being labelled twice. Safe to do unconditionally — across the whole feed
  /// a fasting marker never appears without a rule stated alongside it, so
  /// dropping one never loses information the rule does not carry.
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
      // The fasting rule can be a long sentence, and a Wrap gives its children
      // unbounded width, so without Flexible the pill runs off the edge rather
      // than wrapping inside it.
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

/// Where the day sits in the year: its distance from Pascha, the tone, and the
/// eothinon.
///
/// All three need no data at all, so this is what the screen can always say,
/// including after the published feed lapses. The tone is absent through
/// Bright Week, where the Octoechos is set aside.
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
    // Flexible for the same reason as the pill above: a Wrap hands its
    // children unbounded width, so at the larger text sizes "Fifty-two days
    // after Pascha" runs off the edge instead of wrapping inside the strip.
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
                // A section heading is a fixed string, but at the large text
                // size it is wider than a narrow phone, so it has to be
                // allowed to wrap rather than overflow.
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
