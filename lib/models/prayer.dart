// Prayer texts and the small markup they are authored in.
//
// The format is a deliberately tiny subset of Markdown rather than the real
// thing: prayers need headings, rubrics and paragraphs and nothing else, and a
// parser we own means rubrics can be styled as rubrics instead of as
// blockquotes. It also keeps a Markdown rendering dependency out of the app.
//
//   # Title of the set
//   ## Name of a prayer
//   > A rubric: an instruction, not something to be said aloud
//   Anything else is a paragraph of the prayer itself.
//
// Blank lines separate paragraphs. A line ending in ` (3)` is not special;
// repetition is written out by the author.

/// One line or paragraph within a prayer set.
sealed class PrayerBlock {
  const PrayerBlock();
}

/// The name of a prayer within the set.
class PrayerHeading extends PrayerBlock {
  const PrayerHeading(this.text);

  final String text;
}

/// An instruction to the person praying, not part of the prayer.
///
/// Rendered distinctly, because reading a rubric aloud as though it were the
/// prayer is exactly the confusion the distinction exists to prevent.
class PrayerRubric extends PrayerBlock {
  const PrayerRubric(this.text);

  final String text;
}

/// A paragraph of the prayer itself.
class PrayerText extends PrayerBlock {
  const PrayerText(this.text);

  final String text;
}

/// A named collection of prayers, such as the morning rule.
class PrayerSet {
  const PrayerSet({required this.title, required this.blocks});

  /// Parses the authored form. See the file header for the grammar.
  factory PrayerSet.parse(String source) {
    var title = '';
    final blocks = <PrayerBlock>[];
    final paragraph = StringBuffer();

    void flushParagraph() {
      final text = paragraph.toString().trim();
      if (text.isNotEmpty) blocks.add(PrayerText(text));
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
        blocks.add(PrayerHeading(line.substring(3).trim()));
      } else if (line.startsWith('# ')) {
        flushParagraph();
        // The first level-one heading names the set; any later one is treated
        // as a prayer name rather than silently discarded.
        if (title.isEmpty) {
          title = line.substring(2).trim();
        } else {
          blocks.add(PrayerHeading(line.substring(2).trim()));
        }
      } else if (line.startsWith('> ')) {
        flushParagraph();
        blocks.add(PrayerRubric(line.substring(2).trim()));
      } else {
        // Wrapped lines within a paragraph join with a space, so authors can
        // hard-wrap the source without it showing up in the rendering.
        if (paragraph.isNotEmpty) paragraph.write(' ');
        paragraph.write(line);
      }
    }
    flushParagraph();

    return PrayerSet(title: title, blocks: blocks);
  }

  final String title;
  final List<PrayerBlock> blocks;

  bool get isEmpty => blocks.isEmpty;

  /// Whether there is anything here to actually pray.
  ///
  /// A set can hold real prayers *and* a marked gap — the morning rule does —
  /// so availability keys on this rather than on [hasPlaceholder], which would
  /// hide finished text because the rule is not yet complete.
  bool get hasContent => blocks.any((b) => b is PrayerText);

  /// True when some part of the set is still an unfilled placeholder.
  ///
  /// Lets the UI say a rule is incomplete rather than presenting a stub as
  /// though it were the whole prayer.
  bool get hasPlaceholder =>
      blocks.any((b) => b is PrayerRubric && b.text.startsWith('['));
}

/// An occasion the app offers a rule for.
///
/// Not "time of day": meals and Communion are occasions rather than hours, and
/// declaration order is the order they are listed in, so daily rules come
/// first.
///
/// [slug] is stated rather than derived from [name], so the asset filenames
/// stay snake_case while the Dart identifiers stay camelCase.
enum PrayerOccasion {
  morning('morning'),
  midday('midday'),
  night('night'),
  compline('compline'),
  beforeMeal('before_meal'),
  afterMeal('after_meal'),
  beforeCommunion('before_communion'),
  afterCommunion('after_communion');

  const PrayerOccasion(this.slug);

  final String slug;

  String assetPath(String language) => 'res/prayers/${slug}_$language.md';
}
