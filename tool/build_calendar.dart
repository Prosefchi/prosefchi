// Builds calendar.<lang>.json from the published sources.
//
// This file is the entry point and the orchestration: which sources to run,
// what window to keep, where to write, and what to complain about. Reading any
// one source is `tool/calendar/`, and the schema both this and the app share
// is `lib/models/calendar.dart`.
//
// Usage:
//   dart run tool/build_calendar.dart [options]
//
//   --out DIR      output directory (default: build/calendar)
//   --from DATE    earliest day to keep, YYYY-MM-DD (default: 90 days ago)
//   --to DATE      latest day to keep, YYYY-MM-DD (default: no limit)
//   --cache        reuse previously downloaded responses instead of refetching

import 'dart:convert';
import 'dart:io';

import 'package:prosefchi/liturgics/paschalion.dart';
import 'package:prosefchi/models/calendar.dart';

import 'args.dart';
import 'calendar/goarch.dart';
import 'calendar/source.dart';

/// Warn when a source runs this close to its end. GOARCH populates the
/// calendar in bulk, so a short runway needs to be loud rather than discovered
/// by users.
const runwayWarningDays = 60;

/// The sources a build reads, in the order they are read.
///
/// One file each, named after the source's language.
List<CalendarSource> sources() => [
  for (final entry in feeds.entries) GoarchSource(entry.key, entry.value),
];

Future<void> main(List<String> args) async {
  final options = parseArgs(args);
  final outDir = Directory(options['out'] ?? 'build/calendar');
  await outDir.create(recursive: true);

  final today = _today();
  final from = options['from'] ?? Calendar.dateKey(addDays(today, -90));
  final to = options['to'] ?? '9999-12-31';
  final useCache = options.containsKey('cache');

  for (final source in sources()) {
    final language = source.language;
    final parsed = await source.load(from: from, to: to, useCache: useCache);

    final keys =
        parsed.days.keys
            .where((d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0)
            .toList()
          ..sort();

    if (keys.isEmpty) {
      stderr.writeln('$language: no days in range $from..$to');
      exitCode = 1;
      continue;
    }

    final calendar = Calendar(
      language: language,
      source: source.attribution,
      generatedAt: today,
      sourceUpdatedAt: parsed.sourceUpdatedAt,
      start: DateTime.parse(keys.first),
      end: DateTime.parse(keys.last),
      days: {for (final key in keys) key: parsed.days[key]!},
    );

    final file = File('${outDir.path}/${Calendar.fileName(language)}');
    await file.writeAsString(jsonEncode(calendar.toJson()));

    // Loud on purpose, and the two kinds are reported apart. A rewording that
    // unmaps a rule across the whole of Great Lent would otherwise be a
    // bumped count with five unrelated feast names printed under it, and the
    // days it covers all read as days that do not fast.
    _report(
      language,
      parsed.findings,
      FindingKind.unmappedFastingRule,
      'fasting rule(s) it could not map, so those days publish no rule',
      limit: null,
    );
    _report(
      language,
      parsed.findings,
      FindingKind.unrecognised,
      'unrecognised line(s)',
    );

    final withReadings = keys.where((k) => parsed.days[k]!.hasReadings).length;
    final withFasting = keys
        .where((k) => parsed.days[k]!.fastAllowance != null)
        .length;
    stdout.writeln(
      '$language: ${keys.length} days  ${keys.first}..${keys.last}  '
      '$withReadings with readings  $withFasting with a fasting rule  '
      '${((await file.length()) / 1024).toStringAsFixed(0)} KB  -> ${file.path}',
    );
    stdout.writeln(
      '  upstream last modified '
      '${parsed.sourceUpdatedAt?.toUtc().toIso8601String() ?? "unknown"}',
    );

    final runway = calendar.runwayFrom(today);
    if (runway <= runwayWarningDays) {
      stdout.writeln(
        '  WARNING: $language ends in $runway days (${keys.last}). Upstream '
        'needs to extend it, or the app falls back to computed data only.',
      );
    }
  }
}

/// Prints the findings of one [kind], if there are any.
///
/// [limit] caps how many are listed; null lists them all, which is what the
/// unmappable rules get — they are the ones somebody has to go and fix, and
/// truncating them is how one hides behind the noisier kind.
void _report(
  String language,
  List<Finding> findings,
  FindingKind kind,
  String what, {
  int? limit = 5,
}) {
  final matching = findings.where((f) => f.kind == kind).toList();
  if (matching.isEmpty) return;

  stdout.writeln('  WARNING: $language has ${matching.length} $what:');
  for (final finding in limit == null ? matching : matching.take(limit)) {
    stdout.writeln('    ${finding.date}  ${finding.line}');
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}
