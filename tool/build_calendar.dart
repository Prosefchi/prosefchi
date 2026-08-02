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
import 'calendar/orthocal.dart';
import 'calendar/source.dart';

/// Warn when a source runs this close to its end. GOARCH populates the
/// calendar in bulk, so a short runway needs to be loud rather than discovered
/// by users.
const runwayWarningDays = 60;

/// How far past today a build reaches when `--to` says nothing.
///
/// Not every source has an end of its own — orthocal answers for any year to
/// 4099 — and owning the bound here keeps `--to` meaning one thing for all of
/// them, and lets the runway warning tell upstream stopping from us stopping.
const buildHorizonDays = 400;

/// The sources a build reads, in the order they are read. One file each.
///
/// The Julian calendar is English only, orthocal publishing English only.
List<CalendarSource> sources() => [
  for (final entry in feeds.entries) GoarchSource(entry.key, entry.value),
  const OrthocalSource(),
];

Future<void> main(List<String> args) async {
  final options = parseArgs(args);
  final outDir = Directory(options['out'] ?? 'build/calendar');
  await outDir.create(recursive: true);

  final today = _today();
  final from = options['from'] ?? Calendar.dateKey(addDays(today, -90));
  final to =
      options['to'] ?? Calendar.dateKey(addDays(today, buildHorizonDays));
  final useCache = options.containsKey('cache');

  _assertOneFileEach();

  for (final source in sources()) {
    final language = source.language;
    final label = source.label;
    final parsed = await source.load(from: from, to: to, useCache: useCache);

    final keys =
        parsed.days.keys
            .where((d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0)
            .toList()
          ..sort();

    if (keys.isEmpty) {
      stderr.writeln('$label: no days in range $from..$to');
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

    final file = File(
      '${outDir.path}/${Calendar.fileName(language, style: source.style)}',
    );
    await file.writeAsString(jsonEncode(calendar.toJson()));

    // Reported apart, or a rewording that unmaps a rule across Great Lent is
    // a bumped count with five unrelated feast names printed under it.
    _report(
      label,
      parsed.findings,
      FindingKind.unmappedFastingRule,
      "fasting rule(s) it could not map, so those days do not carry upstream's",
      limit: null,
    );
    _report(
      label,
      parsed.findings,
      FindingKind.unrecognised,
      'unrecognised line(s)',
    );

    final withReadings = keys.where((k) => parsed.days[k]!.hasReadings).length;
    final withFasting = keys
        .where((k) => parsed.days[k]!.fastAllowance != null)
        .length;
    stdout.writeln(
      '$label: ${keys.length} days  ${keys.first}..${keys.last}  '
      '$withReadings with readings  $withFasting with a fasting rule  '
      '${((await file.length()) / 1024).toStringAsFixed(0)} KB  -> ${file.path}',
    );
    stdout.writeln(
      '  upstream last modified '
      '${parsed.sourceUpdatedAt?.toUtc().toIso8601String() ?? "unknown"}',
    );

    // Only where the source ran out first. Ending exactly at the window is
    // this build's own bound, and blaming upstream for it would send whoever
    // reads the log to the wrong place.
    final runway = calendar.runwayFrom(today);
    if (keys.last != to && runway <= runwayWarningDays) {
      stdout.writeln(
        '  WARNING: $label ends in $runway days (${keys.last}). Upstream '
        'needs to extend it, or the app falls back to computed data only.',
      );
    }
  }
}

/// Fails loudly if two sources would write the same file, which nothing else
/// enforces and which is silent: the later one overwrites the earlier.
void _assertOneFileEach() {
  final names = <String>{};
  for (final source in sources()) {
    final name = Calendar.fileName(source.language, style: source.style);
    if (!names.add(name)) throw StateError('two sources both write $name');
  }
}

/// Prints the findings of one [kind], if there are any.
///
/// [limit] null lists them all, which the unmappable rules get: truncating
/// them is how one hides behind the noisier kind.
void _report(
  String label,
  List<Finding> findings,
  FindingKind kind,
  String what, {
  int? limit = 5,
}) {
  final matching = findings.where((f) => f.kind == kind).toList();
  if (matching.isEmpty) return;

  stdout.writeln('  WARNING: $label has ${matching.length} $what:');
  for (final finding in limit == null ? matching : matching.take(limit)) {
    stdout.writeln('    ${finding.date}  ${finding.line}');
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}
