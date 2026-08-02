// The small authored-text format used for prayers and for the welcome pages.
//
//   # Title of the document
//   ## Name of a section
//   > A note: an instruction, not something to be said aloud
//   - An item of a list; `1.` numbers one instead
//   --- a thematic break, which is where a source attribution goes
//   [label](https://example.org) anywhere in a paragraph or a note
//   <!-- a note to whoever maintains the text, which may span lines -->
//   <div>raw HTML, passed straight through to whatever can render it</div>
//   Anything else is a paragraph.
//
// Blank lines separate paragraphs. Anything unrecognised renders literally.
//
// Notes and lists follow Markdown's own continuation rules, and links are
// parsed after a run is joined, so one may be hard-wrapped. CLAUDE.md holds the
// three places this deliberately diverges from Markdown.
//
// HTML is passed through, never parsed, and only the site renders it: the app
// draws widgets, not markup, so a tag in res/ text is invisible there. Words
// between inline tags survive everywhere, because only the tags are markup.

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

/// A raw HTML tag, passed through untouched. A tag only: `<em>Lord</em>` is
/// three spans.
///
/// [text] is empty because a tag is markup rather than words. That is what
/// makes the degradation right in a renderer with no HTML — the tags disappear
/// and the words between them stay.
class MarkupHtml extends MarkupSpan {
  const MarkupHtml(this.html);

  final String html;

  @override
  String get text => '';
}

/// The two things inside a run that are not plain words: a link, then a tag.
///
/// The bounded classes are what stop an unclosed bracket or tag running away
/// with the rest of a prayer, and they leave `[Awaiting text: …]` plain, which
/// is what keeps a placeholder recognisable. Links come first so a URL in a
/// tag's attributes is never read as one.
final _inline = RegExp(r'\[([^\]]*)\]\(([^\s)]+)\)|(<\/?[a-zA-Z][^>]*>)');

/// Splits a joined run into its spans. See the file header for the grammar.
List<MarkupSpan> _spansOf(String source) {
  final spans = <MarkupSpan>[];
  var index = 0;

  for (final match in _inline.allMatches(source)) {
    if (match.start > index) {
      spans.add(MarkupPlain(source.substring(index, match.start)));
    }
    spans.add(switch (match[3]) {
      final tag? => MarkupHtml(tag),
      _ => MarkupLink(text: match[1]!, url: match[2]!),
    });
    index = match.end;
  }
  if (index < source.length) spans.add(MarkupPlain(source.substring(index)));

  return spans;
}

/// One line or paragraph of an authored document.
sealed class MarkupBlock {
  const MarkupBlock();
}

class MarkupHeading extends MarkupBlock {
  const MarkupHeading(this.text);

  final String text;
}

/// A rule between two parts of a document, written `---`.
class MarkupDivider extends MarkupBlock {
  const MarkupDivider();
}

/// A run of lines that are HTML, opened by a line beginning with a tag and
/// closed by a blank line.
class MarkupHtmlBlock extends MarkupBlock {
  const MarkupHtmlBlock(this.html);

  /// Exactly as authored, newlines and all: this is not prose to be reflowed.
  final String html;
}

/// A run of spans: a block of prose, or an item of a list.
mixin MarkupRun {
  List<MarkupSpan> get spans;

  /// The run as one string, for anything that does not render it. A tag reads
  /// as nothing, so the words between two of them survive.
  String get text => spans.map((span) => span.text).join();
}

/// One item of a list. A run, but never a block in its own right.
class MarkupListItem with MarkupRun {
  MarkupListItem(String source) : spans = _spansOf(source);

  @override
  final List<MarkupSpan> spans;
}

/// A run of items, bulleted or numbered. The whole run rather than an item per
/// block, so a renderer is handed the numbering and the grouping.
class MarkupList extends MarkupBlock {
  const MarkupList({required this.ordered, required this.items});

  /// True for `1.`, false for `-`. The authored numbers are not kept: like
  /// Markdown, the position in the run is what numbers an item.
  final bool ordered;

  final List<MarkupListItem> items;
}

/// A block of prose, which may hold links and so is kept as spans.
sealed class MarkupProse extends MarkupBlock with MarkupRun {
  MarkupProse(String source) : spans = _spansOf(source);

  @override
  final List<MarkupSpan> spans;
}

/// An aside addressed to the reader rather than part of the text proper. In a
/// prayer this is a rubric, and must never read as words to be said aloud.
class MarkupNote extends MarkupProse {
  MarkupNote(super.source);
}

/// A paragraph of the text itself.
class MarkupText extends MarkupProse {
  MarkupText(super.source);
}

/// Three or more of the same mark, alone on a line, spaces allowed between.
final _thematicBreak = RegExp(r'^([-*_])(?:\s*\1){2,}$');

/// A line opening a list item. The space is required, as in Markdown, so a
/// hyphenated word does not open a list. Tested after [_thematicBreak], which
/// is what keeps `- - -` a divider.
final _listItem = RegExp(r'^([-*+]|\d+\.)\s+(.*)$');

const _commentOpen = '<!--';
const _commentClose = '-->';

final _tag = RegExp(r'<\/?[a-zA-Z][^>]*>');

/// Requiring a letter after the bracket is what keeps `<!--`, `<3` and a stray
/// `<` from opening a tag.
final _tagStart = RegExp(r'^<\/?[a-zA-Z]');

/// Whether [line] opens a run of HTML.
///
/// A line may begin with a tag and still be prose: `<em>Lord</em>, have mercy.`
/// is a paragraph, and reading it as a block would drop every word from the
/// app, which renders no HTML. So the test is what the line has left once its
/// complete tags are removed — nothing, or another `<` for a tag whose
/// attributes wrap onto the next line.
bool _opensHtmlBlock(String line) {
  if (!_tagStart.hasMatch(line)) return false;

  final remainder = line.replaceAll(_tag, '').trim();
  return remainder.isEmpty || remainder.startsWith('<');
}

/// A parsed document: a title and a sequence of blocks.
class MarkupDocument {
  const MarkupDocument({required this.title, required this.blocks});

  /// Parses the authored form. See the file header for the grammar.
  factory MarkupDocument.parse(String source) {
    var title = '';
    final blocks = <MarkupBlock>[];
    // Runs accumulate so authored line wrapping does not reach the rendering.
    // Only one is ever open.
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

    // Filled from the untrimmed source and never joined. Non-empty exactly
    // while a run of HTML is open, which is the only state needed to know.
    final html = StringBuffer();

    final items = <MarkupListItem>[];
    final item = StringBuffer();
    var ordered = false;

    void flushItem() {
      final text = item.toString().trim();
      if (text.isNotEmpty) items.add(MarkupListItem(text));
      item.clear();
    }

    void flushList() {
      flushItem();
      if (items.isEmpty) return;
      blocks.add(MarkupList(ordered: ordered, items: List.of(items)));
      items.clear();
    }

    void flushAll() {
      final raw = html.toString().trimRight();
      if (raw.isNotEmpty) blocks.add(MarkupHtmlBlock(raw));
      html.clear();

      flush(paragraph, MarkupText.new);
      flush(note, MarkupNote.new);
      flushList();
    }

    var inComment = false;

    for (final raw in source.split('\n')) {
      var line = raw.trim();

      // A comment runs to the first `-->`, which may be many lines later. Text
      // after that marker is kept: a comment must never silently swallow a
      // line of a prayer.
      if (inComment || line.startsWith(_commentOpen)) {
        final start = inComment ? 0 : _commentOpen.length;
        final end = line.indexOf(_commentClose, start);
        if (end < 0) {
          // An unclosed comment runs to the end of the document, as in HTML:
          // a missing `-->` hides what follows rather than corrupting it.
          inComment = true;
          continue;
        }
        inComment = false;
        line = line.substring(end + _commentClose.length).trim();
        if (line.isEmpty) continue;
      }

      // A run of HTML ends at the first blank line. Nothing inside is looked
      // at: that is the point.
      final inHtml = html.isNotEmpty;
      if (inHtml && line.isEmpty) {
        flushAll();
        continue;
      }
      if (inHtml || _opensHtmlBlock(line)) {
        if (!inHtml) flushAll();
        html.writeln(raw.trimRight());
        continue;
      }

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
        // A later `#` becomes a section rather than being discarded.
        if (title.isEmpty) {
          title = line.substring(2).trim();
        } else {
          blocks.add(MarkupHeading(line.substring(2).trim()));
        }
      } else if (line.startsWith('>')) {
        // Opening one run closes the others. Miss one and the block it left
        // open is emitted out of authored order.
        flush(paragraph, MarkupText.new);
        flushList();
        append(note, line.substring(1).trim());
      } else if (_listItem.firstMatch(line) case final marked?) {
        flush(paragraph, MarkupText.new);
        flush(note, MarkupNote.new);
        // Bullets to numbers or back is a second list, not a stray item.
        final numbered = marked[1]!.endsWith('.');
        if (numbered != ordered) flushList();
        flushItem();
        ordered = numbered;
        append(item, marked[2]!.trim());
      } else if (item.isNotEmpty) {
        append(item, line);
      } else if (note.isNotEmpty) {
        // Lazy continuation: a wrapped note that lost its marker is still that
        // note, not a paragraph of prayer text.
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
  /// A document can hold real text *and* a marked gap, so availability keys on
  /// this rather than on [hasPlaceholder], which would hide finished text.
  bool get hasContent => blocks.any((b) => b is MarkupText || b is MarkupList);

  /// True when some part of the document is still an unfilled placeholder.
  bool get hasPlaceholder =>
      blocks.any((b) => b is MarkupNote && b.text.startsWith('['));
}
