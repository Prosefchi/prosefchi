// The small authored-text format used for prayers and for the welcome pages.
//
// A deliberately tiny subset of Markdown rather than the real thing, with its
// own parser: this content needs headings, notes and paragraphs and nothing
// else, and owning the parser is what lets a prayer's rubric be styled as a
// rubric rather than as a blockquote. It also keeps a Markdown rendering
// dependency out of the app.
//
//   # Title of the document
//   ## Name of a section
//   > A note: an instruction, not something to be said aloud
//   --- a thematic break, which is where a source attribution goes
//   [label](https://example.org) anywhere in a paragraph or a note
//   Anything else is a paragraph.
//
// Blank lines separate paragraphs. Anything the parser does not recognise
// falls through and renders literally.
//
// Within that subset the syntax is Markdown's own, because a format that looks
// like Markdown and then quietly disagrees with it is worse than one that does
// not look like Markdown at all. So a note follows the blockquote rules: the
// space after `>` is optional, consecutive marked lines are one note rather
// than one each, and an unmarked line straight after a marked one continues it
// (Markdown calls this lazy continuation). A blank line, a heading or a
// thematic break ends it. Every one of those is a line an author would
// reasonably write, and each used to produce a rubric rendered as prayer text
// or a sentence broken in half.
//
// Links are parsed after a run has been joined, so one may be hard-wrapped
// across two source lines like any other sentence.
//
// Two things real Markdown does that this does not, both deliberate:
//
//   - A `---` is always a thematic break. In Markdown, one directly under a
//     line of text makes that line a heading instead (a setext heading), so
//     the divider an author drew under a paragraph would silently eat it.
//   - Headings hold plain text. A link in one would have nowhere to go that
//     is not already the section it names.

/// A run within a paragraph or a note.
sealed class MarkupSpan {
  const MarkupSpan();

  /// What the span reads as, with no markup around it.
  String get text;
}

/// Words with nothing attached to them.
class MarkupPlain extends MarkupSpan {
  const MarkupPlain(this.text);

  @override
  final String text;
}

/// A label pointing somewhere outside the app, written `[label](url)`.
class MarkupLink extends MarkupSpan {
  const MarkupLink({required this.text, required this.url});

  @override
  final String text;

  final String url;
}

/// A label holds no `]`, and a target no whitespace or `)`, which is enough for
/// an attribution and stops an unclosed bracket swallowing the rest of a
/// prayer. `[Awaiting text: …]` has no target and so stays plain, which is what
/// keeps a placeholder marker recognisable.
final _link = RegExp(r'\[([^\]]*)\]\(([^\s)]+)\)');

/// Splits a joined run into its spans. See the file header for the grammar.
List<MarkupSpan> _spansOf(String source) {
  final spans = <MarkupSpan>[];
  var index = 0;

  for (final match in _link.allMatches(source)) {
    if (match.start > index) {
      spans.add(MarkupPlain(source.substring(index, match.start)));
    }
    spans.add(MarkupLink(text: match[1]!, url: match[2]!));
    index = match.end;
  }
  if (index < source.length) spans.add(MarkupPlain(source.substring(index)));

  return spans;
}

/// One line or paragraph of an authored document.
sealed class MarkupBlock {
  const MarkupBlock();
}

/// The name of a section within the document.
class MarkupHeading extends MarkupBlock {
  const MarkupHeading(this.text);

  final String text;
}

/// A rule between two parts of a document, written `---`.
///
/// It separates rather than says anything, which is what makes it the place to
/// put a source attribution: below the rule is about the text, not part of it.
class MarkupDivider extends MarkupBlock {
  const MarkupDivider();
}

/// A block of prose, which may hold links and so is kept as spans.
sealed class MarkupProse extends MarkupBlock {
  MarkupProse(String source) : spans = _spansOf(source);

  final List<MarkupSpan> spans;

  /// The block as one string, for anything that does not render it.
  String get text => spans.map((span) => span.text).join();
}

/// An aside addressed to the reader rather than part of the text proper.
///
/// In a prayer this is a rubric, and reading one aloud as though it were the
/// prayer is exactly the confusion that styling it apart prevents.
class MarkupNote extends MarkupProse {
  MarkupNote(super.source);
}

/// A paragraph of the text itself.
class MarkupText extends MarkupProse {
  MarkupText(super.source);
}

/// Three or more of the same mark, alone on a line, spaces allowed between.
final _thematicBreak = RegExp(r'^([-*_])(?:\s*\1){2,}$');

/// A parsed document: a title and a sequence of blocks.
class MarkupDocument {
  const MarkupDocument({required this.title, required this.blocks});

  /// Parses the authored form. See the file header for the grammar.
  factory MarkupDocument.parse(String source) {
    var title = '';
    final blocks = <MarkupBlock>[];
    // Both kinds of run accumulate, so that source wrapped for readability
    // does not carry its wrapping into the rendering. Only one is ever open.
    final paragraph = StringBuffer();
    final note = StringBuffer();

    void append(StringBuffer buffer, String text) {
      if (text.isEmpty) return;
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);
    }

    void flush(StringBuffer buffer, MarkupProse Function(String) block) {
      final text = buffer.toString().trim();
      if (text.isNotEmpty) blocks.add(block(text));
      buffer.clear();
    }

    void flushAll() {
      flush(paragraph, MarkupText.new);
      flush(note, MarkupNote.new);
    }

    for (final raw in source.split('\n')) {
      final line = raw.trim();

      // A comment line, for notes to whoever maintains the text.
      if (line.startsWith('<!--')) continue;

      if (line.isEmpty) {
        flushAll();
        continue;
      }

      if (_thematicBreak.hasMatch(line)) {
        flushAll();
        blocks.add(const MarkupDivider());
      } else if (line.startsWith('## ')) {
        flushAll();
        blocks.add(MarkupHeading(line.substring(3).trim()));
      } else if (line.startsWith('# ')) {
        flushAll();
        // The first level-one heading names the document; any later one is
        // treated as a section rather than silently discarded.
        if (title.isEmpty) {
          title = line.substring(2).trim();
        } else {
          blocks.add(MarkupHeading(line.substring(2).trim()));
        }
      } else if (line.startsWith('>')) {
        flush(paragraph, MarkupText.new);
        // Markdown allows one optional space after the marker. The rest of the
        // line is trimmed rather than that single space consumed, which is the
        // same thing here: this subset has no construct where the remaining
        // indentation would mean anything.
        append(note, line.substring(1).trim());
      } else if (note.isNotEmpty) {
        // Lazy continuation: a wrapped note whose second line lost its marker
        // is still that note, not a paragraph of prayer text.
        append(note, line);
      } else {
        append(paragraph, line);
      }
    }
    flushAll();

    return MarkupDocument(title: title, blocks: blocks);
  }

  final String title;
  final List<MarkupBlock> blocks;

  bool get isEmpty => blocks.isEmpty;

  /// Whether there is any prose here, as opposed to only notes.
  ///
  /// A document can hold real text *and* a marked gap — the morning rule does
  /// — so availability keys on this rather than on [hasPlaceholder], which
  /// would hide finished text because the document is not yet complete.
  bool get hasContent => blocks.any((b) => b is MarkupText);

  /// True when some part of the document is still an unfilled placeholder.
  bool get hasPlaceholder =>
      blocks.any((b) => b is MarkupNote && b.text.startsWith('['));
}
