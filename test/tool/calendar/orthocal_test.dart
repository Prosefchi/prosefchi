import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/calendar.dart';

import '../../../tool/calendar/orthocal.dart';
import '../../../tool/calendar/source.dart';

const source = OrthocalSource();

/// One day of the API's response, with only the fields the parser reads.
Map<String, dynamic> apiDay({
  String summaryTitle = 'A day',
  List<String> titles = const [],
  List<String> saints = const [],
  int fastLevel = 0,
  int fastException = 0,
  String fastExceptionDesc = '',
  int feastLevel = 0,
  int tone = 0,
  List<(String source, String display)> readings = const [],
  // The Julian date upstream reports, which nothing may key on.
  int year = 1900,
  int month = 1,
  int day = 1,
}) => {
  'year': year,
  'month': month,
  'day': day,
  'summary_title': summaryTitle,
  'titles': titles,
  'saints': saints,
  'fast_level': fastLevel,
  'fast_exception': fastException,
  'fast_exception_desc': fastExceptionDesc,
  'feast_level': feastLevel,
  'tone': tone,
  'readings': [
    for (final (name, display) in readings)
      {'source': name, 'display': display},
  ],
};

String month31(Map<int, Map<String, dynamic>> overrides) => jsonEncode([
  for (var day = 1; day <= 31; day++) overrides[day] ?? apiDay(),
]);

CalendarDay parse(Map<String, dynamic> json) =>
    source.dayFrom(DateTime(2026, 1, 7), json, []);

void main() {
  group('parseMonth', () {
    test('keys by the requested date, not the one the response states', () {
      // The API takes a Gregorian date and answers with the Julian one:
      // /julian/2026/1/7/ returns the Nativity, reported as 2025-12-25.
      // Keying on the response would move the whole calendar 13 days, which
      // reads as the app being wrong about the date rather than as a bug here.
      final days = source.parseMonth(
        month31({
          7: apiDay(
            summaryTitle: 'Nativity of Christ',
            year: 2025,
            month: 12,
            day: 25,
          ),
        }),
        DateTime(2026),
        [],
      );

      expect(days['2026-01-07']?.title, 'Nativity of Christ');
      expect(days.containsKey('2025-12-25'), isFalse);
      expect(days['2026-01-07']?.date, DateTime(2026, 1, 7));
    });

    test('refuses a month whose length does not match', () {
      // Position is the only thing giving the date, so a short month would
      // silently shift every day after the gap rather than failing.
      expect(
        () => source.parseMonth(jsonEncode([apiDay()]), DateTime(2026), []),
        throwsA(isA<StateError>()),
      );
    });

    test('counts February correctly in a leap year', () {
      final entries = jsonEncode([for (var d = 0; d < 29; d++) apiDay()]);

      expect(source.parseMonth(entries, DateTime(2028, 2), []).length, 29);
      expect(
        () => source.parseMonth(entries, DateTime(2026, 2), []),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('fasting', () {
    FastAllowance? allowance(int level, int exception) =>
        parse(apiDay(fastLevel: level, fastException: exception)).fastAllowance;

    test('a season with nothing lifted is strict', () {
      expect(allowance(2, 0), FastAllowance.strict);
      expect(allowance(2, 9), FastAllowance.strict);
      expect(allowance(2, 10), FastAllowance.strict);
    });

    test('reads the allowances', () {
      expect(allowance(2, 1), FastAllowance.wineAndOil);
      expect(allowance(2, 3), FastAllowance.wineAndOil);
      expect(allowance(5, 2), FastAllowance.fish);
      expect(allowance(4, 4), FastAllowance.fish);
      expect(allowance(1, 7), FastAllowance.dairyEggsAndFish);
    });

    test('flattens the distinctions the Greek usage does not draw', () {
      // Wine without oil, and the caviar allowance, are Slavic rules with no
      // equivalent here. Recorded as the nearest thing rather than dropped.
      expect(allowance(2, 5), FastAllowance.wineAndOil);
      expect(allowance(2, 6), FastAllowance.wineAndOil);
      expect(allowance(1, 8), FastAllowance.wineAndOil);
    });

    test('a day outside any fast states no rule', () {
      // The same thing the feed says by publishing nothing, so the app's
      // computed weekday fast still applies to it.
      expect(allowance(0, 0), isNull);
      expect(allowance(0, 1), isNull);
      expect(parse(apiDay()).fasts, isFalse);
    });

    test('fast free lifts a fast that would otherwise apply', () {
      // 11 is an override, so it has to win over the season rather than being
      // read as one more allowance within it.
      expect(allowance(0, 11), FastAllowance.free);
      expect(allowance(2, 11), FastAllowance.free);
      expect(parse(apiDay(fastLevel: 2, fastException: 11)).fasts, isFalse);
    });

    test('reports an exception it does not know', () {
      final findings = <Finding>[];
      source.dayFrom(
        DateTime(2026, 1, 7),
        apiDay(fastLevel: 2, fastException: 99, fastExceptionDesc: 'Squid'),
        findings,
      );

      expect(findings.single.kind, FindingKind.unmappedFastingRule);
      expect(findings.single.line, contains('fast_exception 99'));
      expect(findings.single.date, '2026-01-07');
    });
  });

  group('readings', () {
    test('sorts them into the four slots the schema has', () {
      // Vespers readings are the Old Testament prophecies, which is the one
      // mapping the names do not give away.
      final day = parse(
        apiDay(
          readings: const [
            ('Vespers', 'Genesis 1.1-13'),
            ('Epistle', '1 Corinthians 9.2-12'),
            ('Gospel', 'Matthew 18.23-35'),
            ('11th Matins Gospel', 'John 21.15-25'),
          ],
        ),
      );

      expect(day.oldTestament?.reference, 'Genesis 1.1-13');
      expect(day.epistle?.reference, '1 Corinthians 9.2-12');
      expect(day.gospel?.reference, 'Matthew 18.23-35');
      expect(day.matinsGospel?.reference, 'John 21.15-25');
    });

    test('keeps the first where upstream appoints two', () {
      // A Sunday carries its own epistle and the saint's. The schema has one
      // slot, and the day's own comes first.
      final day = parse(
        apiDay(
          readings: const [
            ('Epistle', '1 Corinthians 9.2-12'),
            ('Epistle', 'Colossians 1.12-18'),
          ],
        ),
      );

      expect(day.epistle?.reference, '1 Corinthians 9.2-12');
    });

    test('drops the readings the schema has nowhere for', () {
      final day = parse(
        apiDay(
          readings: const [
            ('6th Hour', 'Isaiah 3.1-14'),
            ('1st Passion Gospel', 'John 13.31-18.1'),
            ('Great Blessing of Waters', 'Isaiah 35.1-10'),
          ],
        ),
      );

      expect(day.hasReadings, isFalse);
    });

    test('takes the eothinon from the name of the Matins gospel', () {
      // Upstream carries it in the name rather than as a field.
      expect(
        parse(apiDay(readings: const [('1st Matins Gospel', 'x')])).eothinon,
        1,
      );
      expect(
        parse(apiDay(readings: const [('11th Matins Gospel', 'x')])).eothinon,
        11,
      );
    });

    test('a feast Matins gospel is not one of the eleven', () {
      // Written without a number, and it is no eothinon at all.
      final day = parse(
        apiDay(readings: const [('Matins Gospel', 'Luke 1.39-49')]),
      );

      expect(day.matinsGospel?.reference, 'Luke 1.39-49');
      expect(day.eothinon, isNull);
    });
  });

  group('the rest of the day', () {
    test('treats tone 0 as no tone', () {
      // Rendering the sentinel would read as "Tone 0".
      expect(parse(apiDay(tone: 0)).tone, isNull);
      expect(parse(apiDay(tone: 5)).tone, 5);
    });

    test('heads the commemorations with the day itself', () {
      // The same shape the feed has, where the day's own title comes first.
      final day = parse(
        apiDay(
          summaryTitle: '11th Sunday after Pentecost',
          titles: const ['11th Sunday after Pentecost'],
          saints: const ['Gerasimus of Cephalonia'],
        ),
      );

      expect(day.title, '11th Sunday after Pentecost');
      expect(day.saints, [
        '11th Sunday after Pentecost',
        'Gerasimus of Cephalonia',
      ]);
    });

    test('marks only the great feasts', () {
      // The lower levels are typikon service ranks with no equivalent here.
      expect(parse(apiDay(feastLevel: 8)).marks, [DayMark.majorFeast]);
      expect(parse(apiDay(feastLevel: 6)).marks, [DayMark.majorFeast]);
      expect(parse(apiDay(feastLevel: 5)).marks, isEmpty);
      expect(parse(apiDay(feastLevel: 0)).marks, isEmpty);
    });
  });

  group('fileName', () {
    test('the Gregorian calendar keeps the name the app already asks for', () {
      expect(Calendar.fileName('en'), 'calendar.en.json');
      expect(
        Calendar.fileName('en', style: CalendarStyle.gregorian),
        'calendar.en.json',
      );
    });

    test('every other style sits beside it under its own', () {
      expect(
        Calendar.fileName('en', style: CalendarStyle.julian),
        'calendar.en.julian.json',
      );
    });
  });
}
