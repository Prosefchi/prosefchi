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

    test('separates paragraphs on a blank line', () {
      final set = PrayerSet.parse('# Set\n\nFirst line.\n\nSecond line.\n');

      expect(set.blocks.whereType<PrayerText>().map((b) => b.text), [
        'First line.',
        'Second line.',
      ]);
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
