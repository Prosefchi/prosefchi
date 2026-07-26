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
//   Anything else is a paragraph.
//
// Blank lines separate paragraphs. Anything the parser does not recognise
// falls through and renders literally, which is checked against the authored
// files in test/prayer_assets_test.dart rather than at runtime.

/// One line or paragraph of an authored document.
sealed class MarkupBlock {
  const MarkupBlock();
}

/// The name of a section within the document.
class MarkupHeading extends MarkupBlock {
  const MarkupHeading(this.text);

  final String text;
}

/// An aside addressed to the reader rather than part of the text proper.
///
/// In a prayer this is a rubric, and reading one aloud as though it were the
/// prayer is exactly the confusion that styling it apart prevents.
class MarkupNote extends MarkupBlock {
  const MarkupNote(this.text);

  final String text;
}

/// A paragraph of the text itself.
class MarkupText extends MarkupBlock {
  const MarkupText(this.text);

  final String text;
}

/// A parsed document: a title and a sequence of blocks.
class MarkupDocument {
  const MarkupDocument({required this.title, required this.blocks});

  /// Parses the authored form. See the file header for the grammar.
  factory MarkupDocument.parse(String source) {
    var title = '';
    final blocks = <MarkupBlock>[];
    final paragraph = StringBuffer();

    void flushParagraph() {
      final text = paragraph.toString().trim();
      if (text.isNotEmpty) blocks.add(MarkupText(text));
      paragraph.clear();
    }

    for (final raw in source.split('\n')) {
      final line = raw.trim();

      // A comment line, for notes to whoever maintains the text.
      if (line.startsWith('<!--')) continue;

      if (line.isEmpty) {
        flushParagraph();
        continue;
      }

      if (line.startsWith('## ')) {
        flushParagraph();
        blocks.add(MarkupHeading(line.substring(3).trim()));
      } else if (line.startsWith('# ')) {
        flushParagraph();
        // The first level-one heading names the document; any later one is
        // treated as a section rather than silently discarded.
        if (title.isEmpty) {
          title = line.substring(2).trim();
        } else {
          blocks.add(MarkupHeading(line.substring(2).trim()));
        }
      } else if (line.startsWith('> ')) {
        flushParagraph();
        blocks.add(MarkupNote(line.substring(2).trim()));
      } else {
        // Wrapped lines within a paragraph join with a space, so authors can
        // hard-wrap the source without it showing up in the rendering.
        if (paragraph.isNotEmpty) paragraph.write(' ');
        paragraph.write(line);
      }
    }
    flushParagraph();

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
