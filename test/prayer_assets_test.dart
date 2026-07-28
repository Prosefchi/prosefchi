import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/services/calendar_repository.dart'
    show supportedLanguages;

/// Checks the authored prayer files themselves, not the parser.
///
/// That every occasion has a file, that each one parses to something with a
/// title, that an unfinished rule says so, and that the files are reachable as
/// bundled assets at all.
void main() {
  final files =
      Directory('res/prayers')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('every occasion has a file in every language', () {
    final expected = {
      for (final occasion in PrayerOccasion.values)
        for (final language in supportedLanguages) occasion.assetPath(language),
    };
    final actual = files.map((f) => f.path.replaceAll(r'\', '/')).toSet();

    expect(actual, containsAll(expected));
  });

  test('every file parses to a titled, non-empty set', () {
    for (final file in files) {
      final set = PrayerSet.parse(file.readAsStringSync());
      expect(set.isEmpty, isFalse, reason: '${file.path} parsed to nothing');
      expect(set.title, isNotEmpty, reason: '${file.path} has no title');
    }
  });

  test('every rule either has text or says it is awaited', () {
    // Was written as "if it has no text it must carry a marker", which now
    // that every rule is written skips every file and asserts nothing. Stated
    // as the invariant instead, so it holds a file to one or the other rather
    // than only checking the case that no longer occurs — an unfinished rule
    // has to be reported as unavailable, not open onto a blank screen.
    for (final file in files) {
      final set = PrayerSet.parse(file.readAsStringSync());
      expect(
        set.hasContent || set.hasPlaceholder,
        isTrue,
        reason: '${file.path} has neither text nor an [Awaiting text] marker',
      );
    }
  });

  test('every language has a welcome page that parses', () {
    for (final language in supportedLanguages) {
      final file = File('res/welcome_$language.md');
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');

      final document = MarkupDocument.parse(file.readAsStringSync());
      expect(document.title, isNotEmpty, reason: '${file.path} has no title');
      expect(
        document.hasContent,
        isTrue,
        reason: '${file.path} has no prose, only headings or notes',
      );
    }
  });

  test('every file is listed under a bundled asset directory', () {
    // Directory entries in pubspec.yaml are not recursive, so a file added in
    // a new subdirectory would be missing at runtime with no build error.
    final declared = File('pubspec.yaml')
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.startsWith('- res/'))
        .map((line) => line.substring(2))
        .toSet();

    for (final file in files) {
      final directory = '${file.parent.path.replaceAll(r'\', '/')}/';
      expect(
        declared,
        contains(directory),
        reason:
            '$directory is not declared in pubspec.yaml; assets there will be '
            'missing at runtime',
      );
    }
  });
}
