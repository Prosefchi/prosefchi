import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/calendar.dart';

void main() {
  group('DayMark.split', () {
    test('removes the marker and the variation selector with it', () {
      // Upstream writes U+2626 followed by U+FE0F. Dropping only the symbol
      // leaves the selector behind as an invisible leading character.
      final result = DayMark.split('☦️ Athanasius of Mount Athos');

      expect(result.title, 'Athanasius of Mount Athos');
      expect(result.marks, [DayMark.majorFeast]);
      expect(result.title.codeUnits.first, 'A'.codeUnitAt(0));
    });

    test('handles a bare symbol with no variation selector', () {
      expect(DayMark.split('☦ Athanasius').title, 'Athanasius');
    });

    test('reads the fasting markers', () {
      expect(DayMark.split('🍇 Epiphanius, Bishop of Cyprus').marks, [
        DayMark.wineAndOil,
      ]);
      expect(DayMark.split('🐟 Mid-Pentecost').marks, [DayMark.fish]);
      expect(DayMark.split('🧀 Forgiveness Sunday').marks, [DayMark.dairy]);
    });

    test('leaves an unmarked title alone', () {
      final result = DayMark.split('Dormition of St. Anna');

      expect(result.title, 'Dormition of St. Anna');
      expect(result.marks, isEmpty);
    });

    test('does not mistake Greek text for a marker', () {
      final result = DayMark.split('Κοίμησις Ἁγίας Ἄννης, Μητρὸς τῆς Θεοτόκου');

      expect(result.title, 'Κοίμησις Ἁγίας Ἄννης, Μητρὸς τῆς Θεοτόκου');
      expect(result.marks, isEmpty);
    });
  });

  group('Calendar', () {
    Calendar build({String start = '2026-04-27', String end = '2026-08-31'}) =>
        Calendar.fromJson({
          'language': 'en',
          'source': 'https://example.test/feed.ics',
          'generatedAt': '2026-07-26',
          'sourceUpdatedAt': '2025-05-29T23:50:14.000Z',
          'start': start,
          'end': end,
          'days': {
            '2026-07-26': {
              'title': 'Paraskeve the Righteous Martyr',
              'marks': ['majorFeast', 'fish'],
              'saints': ['Paraskeve the Righteous Martyr', 'Hermolaos'],
              'gospel': {
                'reference': 'Mark 5:24-34',
                'text': 'At that time...',
              },
            },
          },
        });

    test('round-trips through JSON', () {
      final json = build().toJson();
      final day = Calendar.fromJson(json).forDate(DateTime(2026, 7, 26))!;

      expect(day.title, 'Paraskeve the Righteous Martyr');
      expect(day.marks, [DayMark.majorFeast, DayMark.fish]);
      expect(day.isMajorFeast, isTrue);
      expect(day.gospel?.reference, 'Mark 5:24-34');
      expect(day.epistle, isNull);
      expect(Calendar.fromJson(json).sourceUpdatedAt, isNotNull);
    });

    test('ignores marks it does not recognise', () {
      // A newer generator adding a marker must not crash an older app.
      final day = CalendarDay.fromJson('2026-07-26', {
        'title': 'Some Day',
        'marks': ['fish', 'somethingNew'],
      });

      expect(day.marks, [DayMark.fish]);
    });

    test('covers only its published window', () {
      final calendar = build();

      expect(calendar.covers(DateTime(2026, 7, 26)), isTrue);
      expect(calendar.covers(DateTime(2026, 9, 1)), isFalse);
      expect(calendar.forDate(DateTime(2026, 9, 1)), isNull);
    });

    test('reports runway across a DST boundary', () {
      // Greece falls back on the last Sunday of October. A local subtraction
      // over that boundary reports a day short.
      final calendar = build(end: '2026-11-30');

      expect(calendar.runwayFrom(DateTime(2026, 10, 1)), 60);
    });
  });
}
