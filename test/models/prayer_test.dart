import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';

void main() {
  group('PrayerSet.parse', () {
    test('reads the title, headings, rubrics and paragraphs', () {
      final set = PrayerSet.parse('''
# Morning Prayers

> On rising from sleep, make the sign of the Cross.

## The Beginning

In the name of the Father, and of the Son, and of the Holy Spirit. Amen.

Glory to You, our God, glory to You.
''');

      expect(set.title, 'Morning Prayers');
      expect(set.blocks, [
        isA<PrayerRubric>(),
        isA<PrayerHeading>(),
        isA<PrayerText>(),
        isA<PrayerText>(),
      ]);
      expect((set.blocks[1] as PrayerHeading).text, 'The Beginning');
      expect(
        (set.blocks[3] as PrayerText).text,
        'Glory to You, our God, glory to You.',
      );
    });

    test('joins hard-wrapped lines into one paragraph', () {
      // Authors wrap the source for readability; the wrapping must not survive
      // into the rendering.
      final set = PrayerSet.parse('''
# Set

O Heavenly King, the Comforter, the Spirit of Truth,
who are everywhere present and fill all things.
''');

      expect(set.blocks, hasLength(1));
      expect(
        (set.blocks.single as PrayerText).text,
        'O Heavenly King, the Comforter, the Spirit of Truth, '
        'who are everywhere present and fill all things.',
      );
    });

    test('reads a rubric whether or not a space follows the marker', () {
      // Markdown makes the space optional. Requiring it meant `>Τρίς.` fell
      // through to a paragraph and was rendered as words to be said aloud,
      // with the marker still visible in front of them.
      final set = PrayerSet.parse('# Set\n\n>Say three times.\n');

      expect(
        (set.blocks.single as PrayerRubric).text,
        'Say three times.',
        reason: 'a rubric, not a paragraph beginning with >',
      );
    });

    test('joins a hard-wrapped rubric into one', () {
      // Every rubric is padded away from what precedes it, so a sentence split
      // across two of them rendered with a gap in the middle. The welcome page
      // shipped exactly this.
      final set = PrayerSet.parse('''
# Set

> The saints, feasts, and readings are sourced from the calendar of the Greek
> Orthodox Archdiocese of America.
''');

      expect(set.blocks, hasLength(1));
      expect(
        (set.blocks.single as PrayerRubric).text,
        'The saints, feasts, and readings are sourced from the calendar of the '
        'Greek Orthodox Archdiocese of America.',
      );
    });

    test('continues a rubric onto a line that lost its marker', () {
      final set = PrayerSet.parse(
        '# Set\n\n> On rising from sleep,\nmake the sign of the Cross.\n',
      );

      expect(set.blocks, hasLength(1));
      expect(
        (set.blocks.single as PrayerRubric).text,
        'On rising from sleep, make the sign of the Cross.',
      );
    });

    test('separates two rubrics on a blank line', () {
      final set = PrayerSet.parse('# Set\n\n> First.\n\n> Second.\n');

      expect(set.blocks.whereType<PrayerRubric>().map((b) => b.text), [
        'First.',
        'Second.',
      ]);
    });

    test('ends a rubric at a heading', () {
      // No blank line, so only the heading separates them.
      final set = PrayerSet.parse(
        '# Set\n\n> Say three times.\n## Trisagion\n',
      );

      expect(set.blocks, [isA<PrayerRubric>(), isA<PrayerHeading>()]);
      expect((set.blocks.last as PrayerHeading).text, 'Trisagion');
    });

    test('separates paragraphs on a blank line', () {
      final set = PrayerSet.parse('# Set\n\nFirst line.\n\nSecond line.\n');

      expect(set.blocks.whereType<PrayerText>().map((b) => b.text), [
        'First line.',
        'Second line.',
      ]);
    });

    test('reads a link out of a paragraph', () {
      final set = PrayerSet.parse(
        '# Set\n\n[Source](https://orthodox-prayer-book.org/en/proimiaki/)\n',
      );

      final spans = (set.blocks.single as PrayerText).spans;
      expect(spans, hasLength(1));
      expect((spans.single as MarkupLink).text, 'Source');
      expect(
        (spans.single as MarkupLink).url,
        'https://orthodox-prayer-book.org/en/proimiaki/',
      );
    });

    test('keeps the words around a link', () {
      final set = PrayerSet.parse(
        '# Set\n\nFrom [there](https://x.org) only.\n',
      );
      final block = set.blocks.single as PrayerText;

      expect(block.spans.map((s) => s.text), ['From ', 'there', ' only.']);
      expect(
        block.text,
        'From there only.',
        reason: 'the plain reading drops the markup, not the label',
      );
    });

    test('reads a link that was hard-wrapped across two lines', () {
      // Links are parsed once the run is joined, so wrapping the source is as
      // safe here as it is in a paragraph.
      final set = PrayerSet.parse(
        '# Set\n\nSee [the\nsource](https://x.org).\n',
      );

      final link = (set.blocks.single as PrayerText).spans[1] as MarkupLink;
      expect(link.text, 'the source');
      expect(link.url, 'https://x.org');
    });

    test('leaves a placeholder marker alone', () {
      // `[Awaiting text: …]` is a bracket with no target after it, and it has
      // to stay plain or hasPlaceholder stops recognising it.
      final set = PrayerSet.parse('# Set\n\n> [Awaiting text: the rule.]\n');

      expect(
        (set.blocks.single as PrayerRubric).spans.single,
        isA<MarkupPlain>(),
      );
      expect(set.hasPlaceholder, isTrue);
    });

    test('reads a thematic break', () {
      final set = PrayerSet.parse(
        '# Set\n\nAmen.\n\n---\n\n[Source](https://x.org)\n',
      );

      expect(set.blocks, [
        isA<PrayerText>(),
        isA<PrayerDivider>(),
        isA<PrayerText>(),
      ]);
    });

    test('ends a rubric at a thematic break', () {
      // No blank line between them, so only the rule separates them.
      final set = PrayerSet.parse('# Set\n\n> Say three times.\n---\n');

      expect(set.blocks, [isA<PrayerRubric>(), isA<PrayerDivider>()]);
    });

    test('does not take a divider for a heading', () {
      // In Markdown proper, `---` under a line of text makes it a heading. Here
      // it stays a rule, so a divider drawn under a paragraph cannot eat it.
      final set = PrayerSet.parse('# Set\n\nAmen.\n---\n');

      expect(set.blocks, [isA<PrayerText>(), isA<PrayerDivider>()]);
      expect((set.blocks.first as PrayerText).text, 'Amen.');
    });

    test('drops maintainer comments', () {
      final set = PrayerSet.parse('''
<!-- a note to whoever maintains this text -->
# Set

Amen.
''');

      expect(set.title, 'Set');
      expect(set.blocks, hasLength(1));
    });

    test('keeps polytonic Greek intact', () {
      final set = PrayerSet.parse(
        '# Τρισάγιον\n\nἍγιος ὁ Θεός, Ἅγιος Ἰσχυρός, Ἅγιος Ἀθάνατος, ἐλέησον ἡμᾶς.\n',
      );

      expect(set.title, 'Τρισάγιον');
      expect(
        (set.blocks.single as PrayerText).text,
        'Ἅγιος ὁ Θεός, Ἅγιος Ἰσχυρός, Ἅγιος Ἀθάνατος, ἐλέησον ἡμᾶς.',
      );
    });

    test('treats a second level-one heading as a prayer name', () {
      // Rather than silently discarding it, which would lose text.
      final set = PrayerSet.parse('# Set\n\n# Another\n\nAmen.\n');

      expect(set.title, 'Set');
      expect((set.blocks.first as PrayerHeading).text, 'Another');
    });

    test('flags a set that is still a placeholder', () {
      final placeholder = PrayerSet.parse(
        '# Midday Prayers\n\n> [Awaiting text: the midday rule.]\n',
      );
      final real = PrayerSet.parse('# Set\n\n> Make the sign of the Cross.\n');

      expect(placeholder.hasPlaceholder, isTrue);
      expect(real.hasPlaceholder, isFalse);
    });

    test('is empty for empty source', () {
      expect(PrayerSet.parse('').isEmpty, isTrue);
      expect(PrayerSet.parse('\n\n  \n').isEmpty, isTrue);
    });
  });

  group('PrayerOccasion.forTime', () {
    PrayerOccasion? at(int hour, [int minute = 0]) =>
        PrayerOccasion.forTime(DateTime(2026, 7, 26, hour, minute));

    test('names the rule each window belongs to', () {
      expect(at(6), PrayerOccasion.morning);
      expect(at(9, 30), PrayerOccasion.morning);
      expect(at(12), PrayerOccasion.midday);
      expect(at(14, 59), PrayerOccasion.midday);
      expect(at(18), PrayerOccasion.night);
      expect(at(21, 59), PrayerOccasion.night);
    });

    test('gives a boundary to the window it opens', () {
      // Half-open, so noon is the midday rule rather than the last minute of
      // the morning. Every boundary is a whole hour, which is what lets this
      // read the hour alone.
      expect(at(11, 59), PrayerOccasion.morning);
      expect(at(12), PrayerOccasion.midday);
      expect(at(15), isNull);
      expect(at(22), isNull);
    });

    test('names no rule between the windows', () {
      // The gaps are the point: offering the morning rule at four in the
      // afternoon would be worse than offering nothing.
      expect(at(0), isNull);
      expect(at(5, 59), isNull);
      expect(at(16), isNull);
      expect(at(23, 59), isNull);
    });

    test('is not the reminder the user set', () {
      // A reminder is the moment someone asked to be nudged at, and the
      // defaults sit outside these windows on purpose — the compline one at
      // 22:00 belongs to no window at all.
      expect(at(22), isNull);
      expect(
        at(7),
        PrayerOccasion.morning,
        reason: 'the hour decides, not what any reminder is set to',
      );
    });
  });

  group('PrayerOccasion', () {
    test('builds the asset path from the slug, not the identifier', () {
      expect(
        PrayerOccasion.morning.assetPath('el'),
        'res/prayers/morning_el.md',
      );
      expect(
        PrayerOccasion.beforeMeal.assetPath('en'),
        'res/prayers/before_meal_en.md',
        reason: 'camelCase identifier, snake_case filename',
      );
    });
  });
}
