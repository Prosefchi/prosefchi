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
//   - An item of a list; `1.` numbers one instead
//   --- a thematic break, which is where a source attribution goes
//   [label](https://example.org) anywhere in a paragraph or a note
//   <!-- a note to whoever maintains the text, which may span lines -->
//   <div>raw HTML, passed straight through to whatever can render it</div>
//   Anything else is a paragraph.
//
// Blank lines separate paragraphs. Anything the parser does not recognise
// falls through and renders literally.
//
// HTML is passed through rather than parsed. A line that is only tags opens a
// run of HTML that ends at the next blank line; tags among words are kept as
// they stand and the words around them are still text. Nothing here knows what
// any tag means or which ones pair up, and it does not need to.
//
// **A renderer with nowhere to put HTML shows none of it.** The app is one:
// Flutter draws widgets, not markup. So HTML belongs in the site/ documents,
// whose target is a browser, and prayer text under res/ should stay inside the
// subset — an author who reaches for a tag there will find it invisible in the
// app that is the whole reason the prayers are bundled. Words *between* inline
// tags survive everywhere, because only the tags are markup.
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
// A list follows the same rules: consecutive marked lines are one list, an
// unmarked line continues the item above, and a blank line ends it. Markdown
// keeps a list open across a blank line and this does not, which is the one
// place the two differ. Items do not nest.
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

/// A raw HTML tag, passed through untouched.
///
/// A tag only — `<em>Lord</em>` is three spans, the two tags and the words
/// between them. Nothing here understands nesting or which tags pair with
/// which, and it does not need to: passing a tag through is the whole job.
///
/// [text] is empty because a tag is markup rather than words. That is what
/// makes the degradation right in a renderer with no HTML: the tags disappear
/// and the words between them stay.
class MarkupHtml extends MarkupSpan {
  const MarkupHtml(this.html);

  /// The tag exactly as authored.
  final String html;

  @override
  String get text => '';
}

/// The two things inside a run that are not plain words: a link, then a tag.
///
/// A link label holds no `]`, and a target no whitespace or `)`, which is
/// enough for an attribution and stops an unclosed bracket swallowing the rest
/// of a prayer. `[Awaiting text: …]` has no target and so stays plain, which is
/// what keeps a placeholder marker recognisable.
///
/// A tag is `<`, an optional `/`, a letter, and everything up to the first `>`.
/// Requiring a letter is what keeps a stray `<` in prose from opening one, and
/// stopping at `>` is why an unclosed tag cannot run away with the paragraph.
///
/// The link alternative comes first so that a URL inside a tag's attributes is
/// never mistaken for one — the tag is consumed whole.
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

/// A run of lines that are HTML, passed through untouched.
///
/// Opened by a line beginning with a tag and closed by a blank line, which is
/// close enough to how Markdown itself decides. Line breaks are preserved
/// rather than joined the way a paragraph's are: this is not prose being
/// reflowed, and an author who wrote it over several lines meant to.
///
/// **Only a renderer with somewhere to put HTML shows this.** The app has
/// none — Flutter draws widgets, not markup — so it renders nothing at all
/// there. That makes HTML a thing for `site/` files, where the target is a
/// browser; prayer text under `res/` should stay in the subset, or it will be
/// invisible in the app that is the reason the prayers are bundled.
class MarkupHtmlBlock extends MarkupBlock {
  const MarkupHtmlBlock(this.html);

  /// The lines exactly as authored, newlines and all.
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

/// A run of items, bulleted or numbered.
///
/// The whole run rather than an item per block, so a renderer is handed the
/// numbering and the grouping rather than having to recover them.
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

/// A line opening a list item: the marker, a space, then the item.
///
/// The space is required, as in Markdown, so a hyphenated word does not open a
/// list. Tested after [_thematicBreak], which is what keeps `- - -` a divider.
final _listItem = RegExp(r'^([-*+]|\d+\.)\s+(.*)$');

const _commentOpen = '<!--';
const _commentClose = '-->';

/// A complete tag, used to test what a line is left with once its tags are
/// taken away.
final _tag = RegExp(r'<\/?[a-zA-Z][^>]*>');

/// A line beginning with a tag. Requiring a letter after the bracket is what
/// keeps `<!--`, `<3` and a stray `<` out.
final _tagStart = RegExp(r'^<\/?[a-zA-Z]');

/// Whether [line] opens a run of HTML.
///
/// It has to be asked, because a line may both begin with a tag and be prose —
/// `<em>Lord</em>, have mercy.` is a paragraph with two tags in it, not markup.
/// Getting that wrong would drop the words from the app, which renders no HTML
/// at all, so the test is what the line has left once its complete tags are
/// removed:
///
///   - nothing, so the line is only markup and opens a block;
///   - another `<`, so a tag was left open and runs onto the next line, which
///     is how an `<img>` with its attributes wrapped is written;
///   - words, so this is a paragraph and the tags in it are inline.
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

    // A run of HTML, kept verbatim, so this one is filled from the untrimmed
    // source and never joined. Non-empty exactly while a run is open, which is
    // the only state needed to know whether one is.
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

    // Set while a `<!--` has been opened and not yet closed. Comments are
    // notes to whoever maintains the text and never reach the reader.
    var inComment = false;

    for (final raw in source.split('\n')) {
      var line = raw.trim();

      // A comment runs from `<!--` at the start of a line to the first `-->`,
      // which may be many lines later. Anything after that marker on the
      // closing line is ordinary text and is kept: a comment must never
      // silently swallow a line of a prayer, which is the failure mode this
      // whole format is careful about.
      if (inComment || line.startsWith(_commentOpen)) {
        final start = inComment ? 0 : _commentOpen.length;
        final end = line.indexOf(_commentClose, start);
        if (end < 0) {
          // Unterminated so far, so the rest of this line is comment too. An
          // unclosed comment runs to the end of the document, as it does in
          // HTML; a missing `-->` hides what follows rather than corrupting it.
          inComment = true;
          continue;
        }
        inComment = false;
        line = line.substring(end + _commentClose.length).trim();
        if (line.isEmpty) continue;
      }

      // A run of HTML runs to the first blank line, which is how Markdown
      // itself ends one. Nothing inside is looked at: that is the point.
      final inHtml = html.isNotEmpty;
      if (inHtml && line.isEmpty) {
        flushAll();
        continue;
      }
      if (inHtml || _opensHtmlBlock(line)) {
        // Opening a run closes whatever prose stood above it.
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
        // The first level-one heading names the document; any later one is
        // treated as a section rather than silently discarded.
        if (title.isEmpty) {
          title = line.substring(2).trim();
        } else {
          blocks.add(MarkupHeading(line.substring(2).trim()));
        }
      } else if (line.startsWith('>')) {
        // Each of these opens one run and so closes the others. Miss one and
        // the block it left open is emitted out of authored order.
        flush(paragraph, MarkupText.new);
        flushList();
        // Markdown allows one optional space after the marker. The rest of the
        // line is trimmed rather than that single space consumed, which is the
        // same thing here: this subset has no construct where the remaining
        // indentation would mean anything.
        append(note, line.substring(1).trim());
      } else if (_listItem.firstMatch(line) case final marked?) {
        flush(paragraph, MarkupText.new);
        flush(note, MarkupNote.new);
        // A change from bullets to numbers or back is a second list, not a
        // stray item in the first.
        final numbered = marked[1]!.endsWith('.');
        if (numbered != ordered) flushList();
        flushItem();
        ordered = numbered;
        append(item, marked[2]!.trim());
      } else if (item.isNotEmpty) {
        append(item, line);
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
  bool get hasContent => blocks.any((b) => b is MarkupText || b is MarkupList);

  /// True when some part of the document is still an unfilled placeholder.
  bool get hasPlaceholder =>
      blocks.any((b) => b is MarkupNote && b.text.startsWith('['));
}
