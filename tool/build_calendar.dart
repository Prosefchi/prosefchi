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

import 'package:prosefchi/liturgics/paschalion.dart';
import 'package:prosefchi/models/calendar.dart';

/// The parts a day's description is divided into.
enum Section { saints, epistle, gospel, matinsGospel, oldTestament }

/// A GOARCH feed plus the section headers used in that language.
///
/// The two feeds are authored separately and are not field-identical — Greek
/// carries a handful of readings English lacks — so each is parsed on its own
/// terms and joined only by date.
class Feed {
  const Feed({
    required this.url,
    required this.markers,
    required this.fastingPattern,
    required this.fastFreePattern,
    this.tones = const {},
    this.eothina = const {},
  });

  final String url;

  /// Headers per section, in the order they should be tried. Upstream writes
  /// the Old Testament header both singular and plural, so both are listed.
  final Map<Section, List<String>> markers;

  /// The eight Octoechos tones as upstream names them, to their number.
  final Map<String, int> tones;

  /// The eleven resurrectional Matins gospels as upstream names them.
  final Map<String, int> eothina;

  /// Recognises a line as a statement about fasting.
  ///
  /// A whitelist of the exact phrasings would be brittle — there are five in
  /// English and nine in Greek, and upstream is free to add more — so this
  /// matches the vocabulary they are all built from instead. Anything in that
  /// slot which does not match is reported rather than shown, because a line
  /// there is occasionally a feast name and rendering it as the fasting rule
  /// states something false about the day.
  final String fastingPattern;

  /// Recognises a rule that lifts the fast entirely.
  ///
  /// Greek needs care: Κατάλυσις means a release, and appears in
  /// "Κατάλυσις οἴνου καί ἐλαίου" and "Κατάλυσις ἰχθύος", which are fast days
  /// with an allowance. Only Κατάλυσις Πάντων, a release of everything, is
  /// fast free.
  final String fastFreePattern;
}

const feeds = <String, Feed>{
  'en': Feed(
    url:
        'https://calendar.google.com/calendar/ical/'
        'i0foh8u5am8ui8grpo1svvaun4%40group.calendar.google.com/public/basic.ics',
    markers: {
      Section.saints: ['Saints and Feasts:'],
      Section.epistle: ['Epistle Reading:'],
      Section.gospel: ['Gospel Reading:', 'Gospel Readings:'],
      Section.matinsGospel: ['Matins Gospel Reading:'],
      Section.oldTestament: [
        'Old Testament Readings:',
        'Old Testament Reading:',
      ],
    },
    tones: {
      'Tone One': 1,
      'Tone Two': 2,
      'Tone Three': 3,
      'Tone Four': 4,
      'Plagal of the First Tone': 5,
      'Plagal of the Second Tone': 6,
      'Grave Tone': 7,
      'Plagal of the Fourth Tone': 8,
    },
    fastingPattern: r'\bFast\b|\bAbstain|Allowed',
    fastFreePattern: 'Fast Free',
    eothina: {
      'First Orthros Gospel': 1,
      'Second Orthros Gospel': 2,
      'Third Orthros Gospel': 3,
      'Fourth Orthros Gospel': 4,
      'Fifth Orthros Gospel': 5,
      'Sixth Orthros Gospel': 6,
      'Seventh Orthros Gospel': 7,
      'Eighth Orthros Gospel': 8,
      'Ninth Orthros Gospel': 9,
      'Tenth Orthros Gospel': 10,
      'Eleventh Orthros Gospel': 11,
    },
  ),
  'el': Feed(
    url:
        'https://calendar.google.com/calendar/ical/'
        '6aaps70c37oadvt5erfvpthmuo%40group.calendar.google.com/public/basic.ics',
    markers: {
      Section.saints: ['Ἅγιοι καὶ ἑορταί:'],
      Section.epistle: ['Ἀνάγνωσις Ἐπιστολῆς:'],
      Section.gospel: ['Ἀνάγνωσις Εὐαγγελίου:'],
      Section.matinsGospel: ['Ἀνάγνωσις Εὐαγγελίου Ὄρθρου:'],
      Section.oldTestament: ['Ἀνάγνωσις Παλαιᾱς Διαθήκης:'],
    },
    // Byzantine numbering: the four authentic tones, then the four plagal,
    // of which the seventh is called grave rather than plagal of the third.
    tones: {
      "Ηχος α'": 1,
      "Ηχος β'": 2,
      "Ηχος γ'": 3,
      "Ηχος δ'": 4,
      "Ηχος πλ. α'": 5,
      "Ηχος πλ. β'": 6,
      'Ηχος βαρύς': 7,
      "Ηχος πλ. δ'": 8,
    },
    fastingPattern:
        r'Νηστεί|νηστεί|Κατάλυσ|κατάλυσ|ξηροφαγ|ξεροφαγ|Ἀποχή|Αποχή',
    fastFreePattern: 'Κατάλυσις Πάντων',
    eothina: {
      "Εωθ. Α'": 1,
      "Εωθ. Β'": 2,
      "Εωθ. Γ'": 3,
      "Εωθ. Δ'": 4,
      "Εωθ. Ε'": 5,
      "Εωθ. ΣΤ'": 6,
      "Εωθ. Ζ'": 7,
      "Εωθ. Η'": 8,
      "Εωθ. Θ'": 9,
      "Εωθ. Ι'": 10,
      "Εωθ. ΙΑ'": 11,
    },
  ),
};

// Indexing a String allocates a one-character String per character, and this
// runs over ~32 MB of feed. Comparing code units instead costs nothing.
const _backslash = 0x5C;
const _newline = 0x0A;
const _comma = 0x2C;
const _semicolon = 0x3B;
const _lowerN = 0x6E;
const _upperN = 0x4E;

/// Compiled once and reused across all 3287 entries of both feeds.
///
/// Constructing these inside the per-event loop meant roughly forty thousand
/// regex compilations per build.
final _dtstart = RegExp(r'DTSTART;VALUE=DATE:(\d{8})');
final _lastModified = RegExp(r'\nLAST-MODIFIED:(\d{8}T\d{6}Z)');
final _summary = RegExp(r'\nSUMMARY:(.*)');
final _description = RegExp(r'\nDESCRIPTION:(.*)');
final _folded = RegExp(r'\r?\n[ \t]');

/// The language-specific patterns, compiled on first use and kept.
///
/// [Feed] is const so it cannot hold them itself, and they are needed once per
/// event.
final _compiled = <String, RegExp>{};
RegExp _pattern(String source) =>
    _compiled.putIfAbsent(source, () => RegExp(source));

/// Warn when the feed runs this close to its end. GOARCH populates the calendar
/// in bulk, so a short runway needs to be loud rather than discovered by users.
const runwayWarningDays = 60;

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final outDir = Directory(options['out'] ?? 'build/calendar');
  await outDir.create(recursive: true);

  final today = _today();
  final from = options['from'] ?? Calendar.dateKey(addDays(today, -90));
  final to = options['to'] ?? '9999-12-31';

  for (final entry in feeds.entries) {
    final lang = entry.key;
    final feed = entry.value;

    final ics = await _load(
      feed.url,
      lang,
      useCache: options.containsKey('cache'),
    );
    final parsed = parseEvents(ics, feed);

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

    if (parsed.unparsed.isNotEmpty) {
      // Loud on purpose. A line here is a format upstream has changed or a
      // header we do not know, and the previous one of those showed the wrong
      // Gospel on 648 days before anyone noticed.
      stdout.writeln(
        '  WARNING: $lang has ${parsed.unparsed.length} unrecognised '
        'line(s) in the saints section:',
      );
      for (final line in parsed.unparsed.take(5)) {
        stdout.writeln('    $line');
      }
    }

    final withReadings = keys.where((k) => parsed.days[k]!.hasReadings).length;
    final withFasting = keys
        .where((k) => parsed.days[k]!.fasting != null)
        .length;
    stdout.writeln(
      '$lang: ${keys.length} days  ${keys.first}..${keys.last}  '
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
({
  Map<String, CalendarDay> days,
  DateTime? sourceUpdatedAt,
  List<String> unparsed,
})
parseEvents(String ics, Feed feed) {
  // RFC 5545 folds long lines with CRLF + a single space or tab. Unfold before
  // anything else, or DESCRIPTION arrives in 75-octet fragments.
  final unfolded = ics.replaceAll(_folded, '');

  final result = <String, CalendarDay>{};
  final unparsed = <String>[];
  DateTime? sourceUpdatedAt;

  for (final block in unfolded.split('BEGIN:VEVENT').skip(1)) {
    final compact = _dtstart.firstMatch(block)?.group(1);
    if (compact == null) continue;

    final modified = _lastModified.firstMatch(block)?.group(1);
    if (modified != null) {
      final parsed = DateTime.parse(modified);
      if (sourceUpdatedAt == null || parsed.isAfter(sourceUpdatedAt)) {
        sourceUpdatedAt = parsed;
      }
    }

    final date =
        '${compact.substring(0, 4)}-${compact.substring(4, 6)}-'
        '${compact.substring(6)}';
    final summary = _summary.firstMatch(block)?.group(1) ?? '';
    final description = _description.firstMatch(block)?.group(1) ?? '';

    final parts = sections(unescapeIcs(description), feed);
    final headline = DayMark.split(unescapeIcs(summary));
    final saints = commemorations(parts[Section.saints], feed);
    for (final line in saints.unparsed) {
      unparsed.add('$date  $line');
    }

    result[date] = CalendarDay(
      date: DateTime.parse(date),
      title: headline.title,
      marks: headline.marks,
      saints: saints.saints,
      fasting: saints.fasting,
      // Decided here rather than in the app: the phrasings are upstream's
      // vocabulary and the app should never have to interpret them. No rule
      // stated means an ordinary day, which does not fast.
      fasts:
          saints.fasting != null &&
          !_pattern(feed.fastFreePattern).hasMatch(saints.fasting!),
      tone: saints.tone,
      eothinon: saints.eothinon,
      epistle: readingFrom(parts[Section.epistle]),
      gospel: readingFrom(parts[Section.gospel]),
      matinsGospel: readingFrom(parts[Section.matinsGospel]),
      oldTestament: readingFrom(parts[Section.oldTestament]),
    );
  }
  return (days: result, sourceUpdatedAt: sourceUpdatedAt, unparsed: unparsed);
}

/// Splits the saints section into everything upstream packs into it.
///
/// Only the first paragraph lists commemorations. What follows is a handful of
/// single-line facts about the day — the fasting rule, the tone, the eothinon —
/// which have to be told apart line by line rather than lumped together:
///
///     Fast Day (Fish Allowed)
///     Tone Three
///     Sixth Orthros Gospel
///
/// Splitting the whole section on `;` glued all of it onto the last saint, and
/// in Greek, where `;` is the question mark, chopped prose into fragments.
({
  List<String> saints,
  String? fasting,
  int? tone,
  int? eothinon,
  List<String> unparsed,
})
commemorations(String? body, Feed feed) {
  const empty = (
    saints: <String>[],
    fasting: null,
    tone: null,
    eothinon: null,
    unparsed: <String>[],
  );
  if (body == null || body.isEmpty) return empty;

  final paragraphs = body
      .split('\n\n')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (paragraphs.isEmpty) return empty;

  int? tone;
  int? eothinon;
  final fasting = <String>[];
  final unparsed = <String>[];
  final isFasting = _pattern(feed.fastingPattern);

  for (final paragraph in paragraphs.skip(1)) {
    for (final raw in paragraph.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (feed.tones[line] case final value?) {
        tone = value;
      } else if (feed.eothina[line] case final value?) {
        eothinon = value;
      } else if (isFasting.hasMatch(line)) {
        fasting.add(line);
      } else {
        unparsed.add(line);
      }
    }
  }

  return (
    saints: paragraphs.first
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    fasting: fasting.isEmpty ? null : fasting.join(' '),
    tone: tone,
    eothinon: eothinon,
    unparsed: unparsed,
  );
}

/// Splits a section body into its citation and the reading text.
///
/// Public, like the other parsing helpers here, so test/tool can exercise them
/// directly. This file is not under lib/ and so never ships.
///
/// Null for the days with no such reading, which is normal: only about a fifth
/// of days appoint a Matins gospel or an Old Testament reading.
Reading? readingFrom(String? body) {
  if (body == null || body.isEmpty) return null;
  final split = body.indexOf('\n');
  if (split < 0) return Reading(reference: body.trim());
  return Reading(
    reference: body.substring(0, split).trim(),
    text: body.substring(split + 1).trim(),
  );
}

/// Slices a description into its sections.
///
/// Markers are matched only at the start of a line. Searching anywhere would
/// find "Gospel Reading:" inside "Matins Gospel Reading:" and report the
/// Matins reading as the day's Gospel, which it did on 648 days.
///
/// Every section upstream writes has to be listed, not just the ones we keep:
/// a section that is not recognised does not end the one before it, so its
/// whole text is absorbed into the previous section.
Map<Section, String> sections(String description, Feed feed) {
  final found = <(int, Section, int)>[];
  for (final entry in feed.markers.entries) {
    for (final marker in entry.value) {
      final index = _lineStartIndexOf(description, marker);
      if (index != null) {
        found.add((index, entry.key, marker.length));
        break;
      }
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));

  final result = <Section, String>{};
  for (var i = 0; i < found.length; i++) {
    final (start, section, markerLength) = found[i];
    final end = i + 1 < found.length ? found[i + 1].$1 : description.length;
    result[section] = description.substring(start + markerLength, end).trim();
  }
  return result;
}

/// The index of [marker] where it begins a line, or null if it never does.
int? _lineStartIndexOf(String text, String marker) {
  if (text.startsWith(marker)) return 0;
  final index = text.indexOf('\n$marker');
  return index < 0 ? null : index + 1;
}

String unescapeIcs(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit != _backslash || i + 1 >= value.length) {
      out.writeCharCode(unit);
      continue;
    }
    switch (value.codeUnitAt(++i)) {
      case _lowerN:
      case _upperN:
        out.writeCharCode(_newline);
      case final escaped
          when escaped == _comma ||
              escaped == _semicolon ||
              escaped == _backslash:
        out.writeCharCode(escaped);
      case final other:
        out
          ..writeCharCode(_backslash)
          ..writeCharCode(other);
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
