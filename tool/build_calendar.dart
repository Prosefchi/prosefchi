// Builds assets/data/calendar.<lang>.json from the GOARCH iCal feeds.
//
// The feeds are ~32 MB combined and Google serves them with `no-store`, so no
// CDN or client can cache them. This runs in CI instead; the app fetches the
// small JSON produced here.
//
// Usage:
//   dart run tool/build_calendar.dart [options]
//
//   --out DIR      output directory (default: build/calendar)
//   --from DATE    earliest day to keep, YYYY-MM-DD (default: 90 days ago)
//   --to DATE      latest day to keep, YYYY-MM-DD (default: no limit)
//   --cache        reuse previously downloaded .ics instead of refetching

import 'dart:convert';
import 'dart:io';

import 'package:prosefchi/models/calendar.dart';

/// A GOARCH feed plus the section headers used in that language.
///
/// The two feeds are authored separately and are not field-identical — Greek
/// carries a handful of readings English lacks — so each is parsed on its own
/// terms and joined only by date.
class Feed {
  const Feed({
    required this.url,
    required this.saints,
    required this.epistle,
    required this.gospel,
  });

  final String url;
  final String saints;
  final String epistle;
  final String gospel;

  List<String> get markers => [saints, epistle, gospel];
}

const feeds = <String, Feed>{
  'en': Feed(
    url:
        'https://calendar.google.com/calendar/ical/'
        'i0foh8u5am8ui8grpo1svvaun4%40group.calendar.google.com/public/basic.ics',
    saints: 'Saints and Feasts:',
    epistle: 'Epistle Reading:',
    gospel: 'Gospel Reading:',
  ),
  'el': Feed(
    url:
        'https://calendar.google.com/calendar/ical/'
        '6aaps70c37oadvt5erfvpthmuo%40group.calendar.google.com/public/basic.ics',
    saints: 'Ἅγιοι καὶ ἑορταί:',
    epistle: 'Ἀνάγνωσις Ἐπιστολῆς:',
    gospel: 'Ἀνάγνωσις Εὐαγγελίου:',
  ),
};

/// Warn when the feed runs this close to its end. GOARCH populates the calendar
/// in bulk, so a short runway needs to be loud rather than discovered by users.
const runwayWarningDays = 60;

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final outDir = Directory(options['out'] ?? 'build/calendar');
  await outDir.create(recursive: true);

  final today = _today();
  final from =
      options['from'] ??
      Calendar.dateKey(today.subtract(const Duration(days: 90)));
  final to = options['to'] ?? '9999-12-31';

  for (final entry in feeds.entries) {
    final lang = entry.key;
    final feed = entry.value;

    final ics = await _load(
      feed.url,
      lang,
      useCache: options.containsKey('cache'),
    );
    final parsed = _parseEvents(ics, feed);

    final keys =
        parsed.days.keys
            .where((d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0)
            .toList()
          ..sort();

    if (keys.isEmpty) {
      stderr.writeln('$lang: no events in range $from..$to');
      exitCode = 1;
      continue;
    }

    final calendar = Calendar(
      language: lang,
      source: feed.url,
      generatedAt: today,
      sourceUpdatedAt: parsed.sourceUpdatedAt,
      start: DateTime.parse(keys.first),
      end: DateTime.parse(keys.last),
      days: {for (final key in keys) key: parsed.days[key]!},
    );

    final file = File('${outDir.path}/calendar.$lang.json');
    await file.writeAsString(jsonEncode(calendar.toJson()));

    final withReadings = keys.where((k) => parsed.days[k]!.hasReadings).length;
    stdout.writeln(
      '$lang: ${keys.length} days  ${keys.first}..${keys.last}  '
      '$withReadings with readings  '
      '${((await file.length()) / 1024).toStringAsFixed(0)} KB  -> ${file.path}',
    );
    stdout.writeln(
      '  upstream last modified '
      '${parsed.sourceUpdatedAt?.toUtc().toIso8601String() ?? "unknown"}',
    );

    final runway = calendar.runwayFrom(today);
    if (runway <= runwayWarningDays) {
      stdout.writeln(
        '  WARNING: $lang feed ends in $runway days (${keys.last}). Upstream '
        'needs to extend it, or the app falls back to computed data only.',
      );
    }
  }
}

Future<String> _load(String url, String lang, {required bool useCache}) async {
  final cache = File('.dart_tool/calendar_cache/$lang.ics');
  if (useCache && cache.existsSync()) {
    stdout.writeln('$lang: using cached ${cache.path}');
    return cache.readAsString();
  }

  stdout.writeln('$lang: fetching feed...');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    final body = await response.transform(utf8.decoder).join();
    await cache.parent.create(recursive: true);
    await cache.writeAsString(body);
    return body;
  } finally {
    client.close();
  }
}

/// Parses VEVENTs into days keyed by ISO date, along with the latest
/// `LAST-MODIFIED` seen anywhere in the feed.
///
/// That timestamp is taken across the whole feed rather than the emitted
/// window, because it answers "has upstream changed at all", which is what
/// decides whether a rebuild is meaningful.
({Map<String, CalendarDay> days, DateTime? sourceUpdatedAt}) _parseEvents(
  String ics,
  Feed feed,
) {
  // RFC 5545 folds long lines with CRLF + a single space or tab. Unfold before
  // anything else, or DESCRIPTION arrives in 75-octet fragments.
  final unfolded = ics.replaceAll(RegExp(r'\r?\n[ \t]'), '');

  final result = <String, CalendarDay>{};
  DateTime? sourceUpdatedAt;

  for (final block in unfolded.split('BEGIN:VEVENT').skip(1)) {
    final compact = RegExp(
      r'DTSTART;VALUE=DATE:(\d{8})',
    ).firstMatch(block)?.group(1);
    if (compact == null) continue;

    final modified = RegExp(
      r'\nLAST-MODIFIED:(\d{8}T\d{6}Z)',
    ).firstMatch(block)?.group(1);
    if (modified != null) {
      final parsed = DateTime.parse(modified);
      if (sourceUpdatedAt == null || parsed.isAfter(sourceUpdatedAt)) {
        sourceUpdatedAt = parsed;
      }
    }

    final date =
        '${compact.substring(0, 4)}-${compact.substring(4, 6)}-'
        '${compact.substring(6)}';
    final summary = RegExp(r'\nSUMMARY:(.*)').firstMatch(block)?.group(1) ?? '';
    final description =
        RegExp(r'\nDESCRIPTION:(.*)').firstMatch(block)?.group(1) ?? '';

    final sections = _sections(_unescape(description), feed.markers);
    final saints = sections[feed.saints];
    final headline = DayMark.split(_unescape(summary));

    result[date] = CalendarDay(
      date: DateTime.parse(date),
      title: headline.title,
      marks: headline.marks,
      saints: saints == null
          ? const []
          : saints
                .split(';')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
      epistle: _reading(sections[feed.epistle]),
      gospel: _reading(sections[feed.gospel]),
    );
  }
  return (days: result, sourceUpdatedAt: sourceUpdatedAt);
}

/// Splits a section body into its citation and the reading text.
///
/// Null for the ~9% of days with no appointed reading, which is normal.
Reading? _reading(String? body) {
  if (body == null || body.isEmpty) return null;
  final split = body.indexOf('\n');
  if (split < 0) return Reading(reference: body.trim());
  return Reading(
    reference: body.substring(0, split).trim(),
    text: body.substring(split + 1).trim(),
  );
}

/// Slices a description into sections keyed by marker.
///
/// Splitting on blank lines does not work: the Gospel text itself contains
/// blank lines. Instead locate each marker and take everything up to the next.
Map<String, String> _sections(String description, List<String> markers) {
  final found = <(int, String)>[];
  for (final marker in markers) {
    final index = description.indexOf(marker);
    if (index >= 0) found.add((index, marker));
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));

  final result = <String, String>{};
  for (var i = 0; i < found.length; i++) {
    final (start, marker) = found[i];
    final end = i + 1 < found.length ? found[i + 1].$1 : description.length;
    result[marker] = description.substring(start + marker.length, end).trim();
  }
  return result;
}

String _unescape(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    if (value[i] != r'\' || i + 1 >= value.length) {
      out.write(value[i]);
      continue;
    }
    switch (value[++i]) {
      case 'n':
      case 'N':
        out.write('\n');
      case ',':
        out.write(',');
      case ';':
        out.write(';');
      case r'\':
        out.write(r'\');
      default:
        out
          ..write(r'\')
          ..write(value[i]);
    }
  }
  return out.toString();
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (!args[i].startsWith('--')) continue;
    final name = args[i].substring(2);
    if (name == 'cache') {
      options[name] = 'true';
    } else if (i + 1 < args.length) {
      options[name] = args[++i];
    }
  }
  return options;
}
