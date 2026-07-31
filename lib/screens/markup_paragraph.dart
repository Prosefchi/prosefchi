import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/markup.dart';
import 'link.dart';

/// A paragraph or a note, with any links in it tappable.
class MarkupParagraph extends StatelessWidget {
  const MarkupParagraph(this.spans, {super.key, this.style, this.launch});

  final List<MarkupSpan> spans;
  final TextStyle? style;

  /// Injectable, as everything reaching a platform channel has to be. The
  /// screens do not thread this through: building a link touches no channel,
  /// so only a test that taps one needs it, and such a test can build this
  /// widget directly.
  final Future<bool> Function(Uri url, {LaunchMode mode})? launch;

  @override
  Widget build(BuildContext context) {
    // Nearly every paragraph is prayer text with no link in it — a rule of a
    // hundred blocks carries one, the source attribution at the end. Those
    // need none of the recognizer bookkeeping below, nor a State to hold it.
    if (spans.every((span) => span is MarkupPlain)) {
      return Text(spans.map((span) => span.text).join(), style: style);
    }

    return _LinkedParagraph(spans, style: style, launch: launch);
  }
}

/// The same, where at least one span is a link.
///
/// Stateful only because a [TapGestureRecognizer] has to be disposed, and one
/// built inside `build` never would be.
class _LinkedParagraph extends StatefulWidget {
  const _LinkedParagraph(this.spans, {this.style, this.launch});

  final List<MarkupSpan> spans;
  final TextStyle? style;
  final Future<bool> Function(Uri url, {LaunchMode mode})? launch;

  @override
  State<_LinkedParagraph> createState() => _LinkedParagraphState();
}

class _LinkedParagraphState extends State<_LinkedParagraph> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _open(String url) {
    final target = Uri.tryParse(url);
    if (target != null) openLink(context, target, launch: widget.launch);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Rebuilt with the spans, so a recognizer is never left pointing at a link
    // that is no longer there.
    _disposeRecognizers();

    return Text.rich(
      TextSpan(
        children: [
          for (final span in widget.spans)
            switch (span) {
              MarkupPlain(:final text) => TextSpan(text: text),
              // There is nowhere to put a tag here — this draws widgets, not
              // markup — so it draws nothing, and the words either side of it
              // are their own spans and survive. See markup.dart's header:
              // HTML is for the site's documents.
              MarkupHtml() => const TextSpan(),
              MarkupLink(:final text, :final url) => TextSpan(
                text: text,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                ),
                recognizer: _recognizerFor(url),
              ),
            },
        ],
      ),
      style: widget.style,
    );
  }

  TapGestureRecognizer _recognizerFor(String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
    _recognizers.add(recognizer);
    return recognizer;
  }
}
