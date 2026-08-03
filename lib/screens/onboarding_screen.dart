import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/markup.dart';
import '../models/text_size.dart';
import '../services/calendar_repository.dart'
    show CalendarRepository, supportedLanguages;
import '../services/document_repository.dart';
import '../services/notification_service.dart';
import '../services/reminder_refresh.dart';
import '../services/reminder_store.dart';
import '../services/settings_controller.dart';
import 'calendar_style_options.dart';
import 'markup_list.dart';
import 'markup_paragraph.dart';
import 'reminders_screen.dart';

/// The welcome flow, shown once on first launch and replayable from settings:
/// what the app is, how it should read, which prayers to be reminded of.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.documents,
    this.reminderStore,
    this.scheduler,
    this.calendars,
  });

  final DocumentRepository? documents;
  final ReminderStore? reminderStore;
  final ReminderScheduler? scheduler;

  /// Reaches the fasting reminders, which take the day's rule from it.
  final CalendarRepository? calendars;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final DocumentRepository _documents =
      widget.documents ?? DocumentRepository();

  final _controller = PageController();

  String? _language;
  MarkupDocument? _welcome;
  bool _loading = true;
  int _page = 0;

  static const _pageCount = 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The language can change underneath when this is replayed from settings.
    final language = SettingsScope.of(context).effectiveLanguage;
    if (language == _language) return;
    _language = language;
    _load(language);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load(String language) async {
    final welcome = await _documents.welcome(language);
    if (!mounted) return;
    setState(() {
      _welcome = welcome;
      _loading = false;
    });
  }

  Future<void> _finish() async {
    await SettingsScope.of(context).completeOnboarding();
    if (!mounted) return;
    // Replayed from settings it sits on the navigator and should pop; on first
    // launch it is the home widget, and marking it seen swaps it out.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// On a first launch nothing is scheduled yet and this does nothing; it
  /// earns its place when the flow is replayed from settings.
  Future<void> _reschedule() => rescheduleReminders(
    SettingsScope.of(context),
    store: widget.reminderStore,
    calendars: widget.calendars,
    scheduler: widget.scheduler,
  );

  void _next() => _controller.nextPage(
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLast = _page == _pageCount - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _WelcomePage(document: _welcome, loading: _loading),
                  // Before the reminders, because a reader who needs the large
                  // size needs it on the next page too, and because a fasting
                  // reminder armed there is scheduled on the calendar chosen
                  // here.
                  _ReaderPage(reschedule: _reschedule),
                  _RemindersPage(
                    store: widget.reminderStore,
                    scheduler: widget.scheduler,
                    calendars: widget.calendars,
                  ),
                ],
              ),
            ),
            _PageDots(count: _pageCount, current: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              // OverflowBar rather than a Row, which hands its children
              // unbounded width: these two labels are wider than a narrow
              // phone at the larger sizes, and Greek breaks at the middle one.
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: isLast ? null : _finish,
                    child: Text(isLast ? '' : l10n.onboardingSkip),
                  ),
                  FilledButton(
                    onPressed: isLast ? _finish : _next,
                    child: Text(
                      isLast ? l10n.onboardingDone : l10n.onboardingNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.document, required this.loading});

  final MarkupDocument? document;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final welcome = document;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      children: [
        if (welcome != null) ...[
          Text(welcome.title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 20),
          for (final block in welcome.blocks)
            switch (block) {
              MarkupHeading(:final text) => Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 6),
                child: Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              MarkupNote(:final spans) => Padding(
                padding: const EdgeInsets.only(top: 20),
                child: MarkupParagraph(
                  spans,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.hintColor,
                  ),
                ),
              ),
              MarkupText(:final spans) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MarkupParagraph(
                  spans,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ),
              MarkupList() => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MarkupItems(
                  block,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ),
              MarkupDivider() => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(),
              ),
              // HTML is not supported in the app.
              MarkupHtmlBlock() => const SizedBox.shrink(),
            },
        ],
      ],
    );
  }
}

class _RemindersPage extends StatelessWidget {
  const _RemindersPage({
    required this.store,
    required this.scheduler,
    required this.calendars,
  });

  final ReminderStore? store;
  final ReminderScheduler? scheduler;
  final CalendarRepository? calendars;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(top: 32, bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingRemindersTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.onboardingRemindersBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ReminderList(
          store: store,
          scheduler: scheduler,
          calendars: calendars,
          showTimes: false,
        ),
      ],
    );
  }
}

/// Language, text size and calendar: what the reader is given, before they are
/// asked what to be reminded of.
class _ReaderPage extends StatelessWidget {
  const _ReaderPage({required this.reschedule});

  final Future<void> Function() reschedule;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = SettingsScope.of(context);

    return ListView(
      padding: const EdgeInsets.only(top: 32, bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardingReaderTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.onboardingReaderBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _SectionLabel(l10n.language),
        RadioGroup<String?>(
          groupValue: settings.language,
          onChanged: (value) =>
              settings.setLanguage(value).then((_) => reschedule()),
          child: Column(
            children: [
              // Null is a real option: following the device.
              RadioListTile<String?>(
                value: null,
                title: Text(l10n.languageSystem),
              ),
              for (final language in supportedLanguages)
                RadioListTile<String?>(
                  value: language,
                  title: Text(
                    language == 'el'
                        ? l10n.languageGreek
                        : l10n.languageEnglish,
                  ),
                ),
            ],
          ),
        ),
        _SectionLabel(l10n.textSize),
        RadioGroup<TextSize>(
          groupValue: settings.textSize,
          onChanged: (value) {
            if (value != null) settings.setTextSize(value);
          },
          child: Column(
            children: [
              for (final size in TextSize.values)
                RadioListTile<TextSize>(
                  value: size,
                  // Drawn at the size it selects, composed through `over`
                  // because an explicit scaler would replace the inherited one.
                  title: Text(switch (size) {
                    TextSize.small => l10n.textSizeSmall,
                    TextSize.medium => l10n.textSizeMedium,
                    TextSize.large => l10n.textSizeLarge,
                  }, textScaler: size.over(MediaQuery.textScalerOf(context))),
                ),
            ],
          ),
        ),
        _SectionLabel(l10n.calendarStyle),
        CalendarStyleOptions(
          value: settings.calendarStyle,
          onChanged: (style) =>
              settings.setCalendarStyle(style).then((_) => reschedule()),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == current ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: i == current
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.25),
            ),
          ),
      ],
    );
  }
}
