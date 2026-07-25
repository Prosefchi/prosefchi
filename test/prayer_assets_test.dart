import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/services/calendar_repository.dart'
    show supportedLanguages;

/// Checks the authored prayer files themselves, not the parser.
///
/// The parser is deliberately forgiving: anything it does not recognise falls
/// through and renders as literal text. That is the right behaviour at runtime
/// but a poor way to find out you wrote `**Lord**` and shipped the asterisks,
/// so the mistakes are caught here instead.
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

  test('no file uses markup the parser silently ignores', () {
    // Each of these renders as literal characters in the middle of a prayer.
    final unsupported = <String, RegExp>{
      'bold or italic markers': RegExp(r'\*'),
      'underscore emphasis': RegExp(r'(?<!\w)_{2}'),
      'a heading deeper than ##': RegExp(r'^#{3,}\s', multiLine: true),
      'a link': RegExp(r'\[[^\]]*\]\('),
      'a list item': RegExp(r'^\s*([-+]|\d+\.)\s', multiLine: true),
      'a code span': RegExp('`'),
    };

    for (final file in files) {
      final source = file.readAsStringSync();
      unsupported.forEach((description, pattern) {
        expect(
          pattern.hasMatch(source),
          isFalse,
          reason:
              '${file.path} contains $description, which the parser does not '
              'understand and will render literally',
        );
      });
    }
  });

  test('a file with no prayer text says so with a placeholder marker', () {
    // So an unfinished rule is reported as unavailable rather than opening
    // onto a blank screen.
    for (final file in files) {
      final set = PrayerSet.parse(file.readAsStringSync());
      if (set.hasContent) continue;
      expect(
        set.hasPlaceholder,
        isTrue,
        reason: '${file.path} has no text and no [Awaiting text] marker',
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
