import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/markup.dart';

/// Holds an authored `.md` to existing and parsing to something worth showing.
///
/// The parser fails quietly: a missing file, or one whose title line was lost
/// in an edit, renders as a blank page rather than an error.
void expectAuthoredDocument(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');

  final document = MarkupDocument.parse(file.readAsStringSync());
  expect(document.title, isNotEmpty, reason: '$path has no title');
  expect(
    document.hasContent,
    isTrue,
    reason: '$path has no prose, only headings or notes',
  );
}
