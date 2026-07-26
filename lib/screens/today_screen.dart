import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../liturgics/paschalion.dart';
import '../models/calendar.dart';
import '../services/calendar_repository.dart';
import 'settings_screen.dart';

/// The main screen: who is commemorated today, and the appointed readings.
///
/// Draws from the on-disk calendar immediately and refreshes in the background,
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

  /// Reads the cached calendar, then refreshes behind it.
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
    // silent by design: whatever was cached stays put.
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _DateHeadline(date: _date, locale: _language ?? 'en'),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_day case final day?)
              ..._dayContents(context, l10n, day)
            else
              _Fallback(
                date: _date,
                haveCalendar: _haveCalendar,
                onRetry: _retry,
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _dayContents(
    BuildContext context,
    AppLocalizations l10n,
    CalendarDay day,
  ) {
    final theme = Theme.of(context);
    return [
      Text(day.title, style: theme.textTheme.headlineSmall),
      if (day.marks.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mark in day.marks)
              Chip(
                avatar: Text(mark.symbol),
                label: Text(_markLabel(l10n, mark)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
      // The headline is already the first commemoration, so a list of one adds
      // nothing but repetition.
      if (day.saints.length > 1) ...[
        _SectionHeading(l10n.commemorations),
        for (final saint in day.saints)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $saint', style: theme.textTheme.bodyLarge),
          ),
      ],
      if (day.epistle case final epistle?)
        _ReadingSection(heading: l10n.epistleReading, reading: epistle),
      if (day.gospel case final gospel?)
        _ReadingSection(heading: l10n.gospelReading, reading: gospel),
    ];
  }

  static String _markLabel(AppLocalizations l10n, DayMark mark) =>
      switch (mark) {
        DayMark.majorFeast => l10n.markMajorFeast,
        DayMark.wineAndOil => l10n.markWineAndOil,
        DayMark.fish => l10n.markFish,
        DayMark.dairy => l10n.markDairy,
      };
}

class _DateHeadline extends StatelessWidget {
  const _DateHeadline({required this.date, required this.locale});

  final DateTime date;
  final String locale;

  @override
  Widget build(BuildContext context) => Text(
    DateFormat.yMMMMEEEEd(locale).format(date),
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(color: Theme.of(context).hintColor),
  );
}

/// What the app can still say with no calendar data at all.
///
/// The published feed ends on a fixed date and upstream has let it lapse for a
/// year before, so this is a state the app will genuinely sit in, not just a
/// first-launch nicety.
class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.date,
    required this.haveCalendar,
    required this.onRetry,
  });

  final DateTime date;
  final bool haveCalendar;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final offset = daysBetween(orthodoxPascha(date.year), date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          offset >= 0
              ? l10n.daysAfterPascha(offset)
              : l10n.daysUntilPascha(-offset),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        Text(
          haveCalendar ? l10n.noEntryForDay : l10n.calendarNotDownloaded,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 10),
    // Deliberately not uppercased. Greek drops the tonos in all-caps
    // (ΕΥΑΓΓΕΛΙΟ), but Dart's toUpperCase keeps it — 'Ευαγγέλιο' becomes
    // 'ΕΥΑΓΓΈΛΙΟ', which is simply misspelt to a Greek reader.
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        letterSpacing: 0.6,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _ReadingSection extends StatelessWidget {
  const _ReadingSection({required this.heading, required this.reading});

  final String heading;
  final Reading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(heading),
        Text(reading.reference, style: theme.textTheme.titleSmall),
        if (reading.text case final text?) ...[
          const SizedBox(height: 8),
          Text(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
        ],
      ],
    );
  }
}
