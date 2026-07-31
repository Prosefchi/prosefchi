import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/markup.dart';
import '../models/text_size.dart';
import '../services/calendar_repository.dart' show supportedLanguages;
import '../services/document_repository.dart';
import '../services/notification_service.dart';
import '../services/reminder_store.dart';
import '../services/settings_controller.dart';
import 'markup_paragraph.dart';
import 'reminders_screen.dart';

/// The welcome flow, shown once on first launch and replayable from settings.
///
/// Three pages, swiped horizontally: what the app is, how it should read, and
/// which prayers to be reminded of. Reminders all ship off, so the
/// notification permission is only requested when the user switches the first
/// one on here, which is the point at which the prompt makes sense.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    this.documents,
    this.reminderStore,
    this.scheduler,
  });

  final DocumentRepository? documents;
  final ReminderStore? reminderStore;
  final ReminderScheduler? scheduler;

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
    // The welcome text is authored per language, so it reloads if the language
    // changes underneath, which it can when this is replayed from settings.
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
                  // Between the greeting and the reminders: the two settings
                  // that decide how everything after this reads. Asked here
                  // rather than left to be found, because a reader who needs
                  // the large size needs it on the next page too.
                  const _ReaderPage(),
                  _RemindersPage(
                    store: widget.reminderStore,
                    scheduler: widget.scheduler,
                  ),
                ],
              ),
            ),
            _PageDots(count: _pageCount, current: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              // OverflowBar rather than a Row, which hands its children
              // unbounded width: at the larger text sizes these two labels are
              // wider than a narrow phone and ran off the edge. Greek breaks
              // first and breaks at the middle size, not only the largest.
              // This is the pair of actions OverflowBar exists for, and it
              // stacks them rather than clipping when they will not fit.
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
              MarkupDivider() => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(),
              ),
              // As on the prayers screen: no markup renderer here, so a run of
              // HTML takes no space rather than leaving a gap.
              MarkupHtmlBlock() => const SizedBox.shrink(),
            },
        ],
      ],
    );
  }
}

class _RemindersPage extends StatelessWidget {
  const _RemindersPage({required this.store, required this.scheduler});

  final ReminderStore? store;
  final ReminderScheduler? scheduler;

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
        // Times are hidden here: the question at this point is only which
        // prayers, and a picker per row would crowd it.
        ReminderList(store: store, scheduler: scheduler, showTimes: false),
      ],
    );
  }
}

/// Language and text size, the two settings that shape the reading.
class _ReaderPage extends StatelessWidget {
  const _ReaderPage();

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
          onChanged: settings.setLanguage,
          child: Column(
            children: [
              // Null is following the device, which is a real choice and not
              // an absence of one.
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
                  // Drawn at the size it selects, so the choice shows what it
                  // does. Composed onto the platform's own size, since an
                  // explicit scaler would replace it.
                  title: Text(switch (size) {
                    TextSize.small => l10n.textSizeSmall,
                    TextSize.medium => l10n.textSizeMedium,
                    TextSize.large => l10n.textSizeLarge,
                  }, textScaler: size.over(MediaQuery.textScalerOf(context))),
                ),
            ],
          ),
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
