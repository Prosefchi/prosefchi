import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/calendar.dart';

import '../../tool/build_calendar.dart';

/// Wraps a description the way the feed does, as a single folded line.
String event(String date, String summary, String description) =>
    'BEGIN:VEVENT\n'
    'DTSTART;VALUE=DATE:$date\n'
    'SUMMARY:$summary\n'
    'DESCRIPTION:${description.replaceAll('\n', r'\n')}\n'
    'END:VEVENT\n';

void main() {
  group('sections', () {
    test('matches a marker only at the start of a line', () {
      // "Gospel Reading:" occurs inside "Matins Gospel Reading:". Searching
      // anywhere found that one first and reported the Matins reading as the
      // day's Gospel, on 648 days of the feed.
      const description =
          'Saints and Feasts: Andrew\n\n'
          'Matins Gospel Reading: Luke 1:39-49\nAt that time Mary arose.\n\n'
          'Gospel Reading: Luke 10:38-42\nThe Lord entered a village.';

      final parts = sections(description, feeds['en']!);

      expect(parts[Section.gospel], startsWith('Luke 10:38-42'));
      expect(parts[Section.matinsGospel], startsWith('Luke 1:39-49'));
    });

    test('an unlisted section would swallow the one before it', () {
      // Every section upstream writes has to be listed, not only the ones we
      // keep: an unrecognised header does not end the section above it.
      const description =
          'Saints and Feasts: Andrew\n\n'
          'Matins Gospel Reading: Luke 1:39-49\nAt that time Mary arose.';

      final withMatins = sections(description, feeds['en']!);
      expect(withMatins[Section.saints], 'Andrew');

      final blind = sections(
        description,
        const Feed(
          url: 'x',
          fastingPattern: r'\bFast\b',
          markers: {
            Section.saints: ['Saints and Feasts:'],
            Section.gospel: ['Gospel Reading:'],
          },
        ),
      );
      expect(
        blind[Section.saints],
        contains('At that time Mary arose'),
        reason: 'demonstrates the failure the full marker list prevents',
      );
    });

    test('reads the Old Testament header in either spelling', () {
      for (final header in [
        'Old Testament Reading:',
        'Old Testament Readings:',
      ]) {
        final parts = sections(
          'Saints and Feasts: Andrew\n\n$header Genesis 1:1-13\nIn the beginning.',
          feeds['en']!,
        );
        expect(parts[Section.oldTestament], startsWith('Genesis 1:1-13'));
      }
    });

    test('handles a description that opens with a marker', () {
      final parts = sections('Saints and Feasts: Andrew', feeds['en']!);

      expect(parts[Section.saints], 'Andrew');
    });
  });

  group('commemorations', () {
    test('splits only the first paragraph, and keeps the fasting rule', () {
      // The fasting rule follows the commemorations after a blank line.
      // Splitting the whole section on ';' glued it onto the last saint.
      final result = commemorations(
        'Andrew; Peter; Paul\n\nFast Day (Wine and Oil Allowed)',
        feeds['en']!,
      );

      expect(result.saints, ['Andrew', 'Peter', 'Paul']);
      expect(result.fasting, 'Fast Day (Wine and Oil Allowed)');
    });

    test('leaves Greek question marks alone', () {
      // ';' is the Greek question mark. Any prose reaching this function gets
      // chopped at every question, which is how the bug showed itself.
      final result = commemorations(
        'Γενέθλιον τοῦ Ιωάννου Προδρόμου',
        feeds['en']!,
      );

      expect(result.saints, ['Γενέθλιον τοῦ Ιωάννου Προδρόμου']);
    });

    test('is empty for an absent section', () {
      expect(commemorations(null, feeds['en']!).saints, isEmpty);
      expect(commemorations(null, feeds['en']!).fasting, isNull);
      expect(commemorations('', feeds['en']!).saints, isEmpty);
    });

    test('has no fasting rule when only commemorations are given', () {
      expect(commemorations('Andrew; Peter', feeds['en']!).fasting, isNull);
    });

    test('tells the fasting rule, tone and eothinon apart', () {
      // Upstream packs all three into one paragraph, one per line. Joining
      // them put "Tone Three" into the fasting rule.
      final result = commemorations(
        'Andrew\n\nFast Day (Fish Allowed)\nTone Three\nSixth Orthros Gospel',
        feeds['en']!,
      );

      expect(result.saints, ['Andrew']);
      expect(result.fasting, 'Fast Day (Fish Allowed)');
      expect(result.tone, 3);
      expect(result.eothinon, 6);
    });

    test('reads the Byzantine tone names', () {
      // The seventh is called grave rather than plagal of the third.
      expect(commemorations('A\n\nGrave Tone', feeds['en']!).tone, 7);
      expect(
        commemorations('A\n\nPlagal of the Fourth Tone', feeds['en']!).tone,
        8,
      );
      expect(commemorations("A\n\nΗχος βαρύς", feeds['el']!).tone, 7);
      expect(commemorations("A\n\nΗχος πλ. δ'", feeds['el']!).tone, 8);
    });

    test('does not report a feast name as the fasting rule', () {
      // Upstream occasionally puts the feast in that slot. Rendering it as the
      // fasting rule states something false about the day, so it is set aside
      // and reported at build time instead.
      final result = commemorations(
        'Christ is born\n\nThe Theophany of Our Lord and Saviour Jesus Christ',
        feeds['en']!,
      );

      expect(result.fasting, isNull);
      expect(result.unparsed, [
        'The Theophany of Our Lord and Saviour Jesus Christ',
      ]);
    });

    test('recognises a fasting rule that never says the word fast', () {
      // "Wine & Oil Allowed" appears once and matches no other phrasing. The
      // build-time warning is what surfaced it.
      final result = commemorations('A\n\nWine & Oil Allowed', feeds['en']!);

      expect(result.fasting, 'Wine & Oil Allowed');
      expect(result.unparsed, isEmpty);
    });

    test('reads the plural Gospel Readings header', () {
      // Holy Week 2018 and 2019 use it. Unlisted, it swallowed the gospel text
      // into the saints section on six days.
      final parts = sections(
        'Saints and Feasts: Holy Wednesday\n\n'
        'Gospel Readings: John 12:17-50\nAt that time, the crowd.',
        feeds['en']!,
      );

      expect(parts[Section.gospel], startsWith('John 12:17-50'));
      expect(parts[Section.saints], 'Holy Wednesday');
    });

    test('reads the Greek eothinon numerals', () {
      expect(commemorations("A\n\nΕωθ. ΣΤ'", feeds['el']!).eothinon, 6);
      expect(commemorations("A\n\nΕωθ. ΙΑ'", feeds['el']!).eothinon, 11);
    });
  });

  group('parseEvents', () {
    test('keeps the Gospel and the Matins Gospel apart', () {
      final parsed = parseEvents(
        event(
          '20191028',
          'Saint Paraskeve',
          'Saints and Feasts: Paraskeve\n\n'
              'Matins Gospel Reading: Luke 1:39-49, 56\nAt that time Mary arose.\n\n'
              'Epistle Reading: Galatians 3:23-29\nBrethren, before faith came.\n\n'
              'Gospel Reading: Luke 10:38-42, 11:27-28\nThe Lord entered a village.',
        ),
        feeds['en']!,
      );

      final day = parsed.days['2019-10-28']!;
      expect(day.gospel?.reference, 'Luke 10:38-42, 11:27-28');
      expect(day.matinsGospel?.reference, 'Luke 1:39-49, 56');
      expect(day.epistle?.reference, 'Galatians 3:23-29');
      expect(day.saints, ['Paraskeve']);
    });

    test('parses a Greek day without splitting prose on the question mark', () {
      final parsed = parseEvents(
        event(
          '20200624',
          '🐟 Γενέθλιον τοῦ Ιωάννου Προδρόμου',
          'Ἅγιοι καὶ ἑορταί: Γενέθλιον τοῦ Ιωάννου Προδρόμου; Ἐλισάβετ\n\n'
              'Ημέρα Νηστείας (Κατάλυσις ιχθύος)\n\n'
              'Ἀνάγνωσις Εὐαγγελίου Ὄρθρου: Κατὰ Λουκᾶν 1:24-25\n'
              'Τί ἄρα τὸ παιδίον τοῦτο ἔσται; καὶ χεὶρ Κυρίου ἦν μετ᾿ αὐτοῦ.\n\n'
              'Ἀνάγνωσις Εὐαγγελίου: Κατὰ Λουκᾶν 1:1-25',
        ),
        feeds['el']!,
      );

      final day = parsed.days['2020-06-24']!;
      expect(day.saints, ['Γενέθλιον τοῦ Ιωάννου Προδρόμου', 'Ἐλισάβετ']);
      expect(day.fasting, 'Ημέρα Νηστείας (Κατάλυσις ιχθύος)');
      expect(day.matinsGospel?.text, contains('τὸ παιδίον τοῦτο ἔσται;'));
      expect(day.gospel?.reference, 'Κατὰ Λουκᾶν 1:1-25');
      expect(day.marks, [DayMark.fish]);
      expect(day.title, 'Γενέθλιον τοῦ Ιωάννου Προδρόμου');
    });

    test('a day with no readings still parses', () {
      final parsed = parseEvents(
        event('20260726', 'Paraskeve', 'Saints and Feasts: Paraskeve'),
        feeds['en']!,
      );

      final day = parsed.days['2026-07-26']!;
      expect(day.hasReadings, isFalse);
      expect(day.saints, ['Paraskeve']);
    });
  });

  group('readingFrom', () {
    test('splits the citation from the text', () {
      final reading = readingFrom('Mark 5:24-34\nAt that time, a great crowd.');

      expect(reading?.reference, 'Mark 5:24-34');
      expect(reading?.text, 'At that time, a great crowd.');
    });

    test('accepts a citation with no text', () {
      expect(readingFrom('Mark 5:24-34')?.text, isNull);
    });

    test('is null for an absent section', () {
      expect(readingFrom(null), isNull);
      expect(readingFrom(''), isNull);
    });
  });
}
