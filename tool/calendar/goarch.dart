// The GOARCH iCal feeds, and everything needed to read one.
//
// ~32 MB combined and served `no-store`, so nothing can cache them and this
// runs in CI. The helpers are public for `test/tool/`; nothing here ships.

import 'package:prosefchi/models/calendar.dart';

import 'fetch.dart';
import 'source.dart';

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
    required this.fastingRules,
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
  /// Matches the vocabulary rather than the phrasings, so a wording upstream
  /// has not used before is still caught and reported. Its only job now that
  /// [fastingRules] selects: telling a rule we failed to map from a line that
  /// was never one.
  final String fastingPattern;

  /// Every rule upstream states, to what it permits.
  ///
  /// Exact strings, so this is a table to check against the feed rather than a
  /// regex whose coverage has to be argued about. Κατάλυσις is why: it means a
  /// release, appears in three Greek rules, and only Κατάλυσις Πάντων lifts
  /// the fast. Matching the word got the other two wrong.
  final Map<String, FastAllowance> fastingRules;
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
    fastingRules: {
      'Strict Fast': FastAllowance.strict,
      'Fast Day (Wine and Oil Allowed)': FastAllowance.wineAndOil,
      'Wine & Oil Allowed': FastAllowance.wineAndOil,
      'Fast Day (Fish Allowed)': FastAllowance.fish,
      'Fast Day (Dairy, Eggs, and Fish Allowed)':
          FastAllowance.dairyEggsAndFish,
      'Fast Free': FastAllowance.free,
    },
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
    // Nine phrasings for five rules: upstream writes several of them both
    // monotonic and polytonic, and both spellings are in the feed today.
    fastingRules: {
      'Αυστηρή Νηστεία': FastAllowance.strict,
      'ξεροφαγία (αὐστηρή νηστεία)': FastAllowance.strict,
      'Ημέρα Νηστείας (Κατάλυσις οίνου και ελαίου)': FastAllowance.wineAndOil,
      'Κατάλυσις οἴνου καί ἐλαίου': FastAllowance.wineAndOil,
      'Ημέρα Νηστείας (Κατάλυσις ιχθύος, ελαίου και οίνου)': FastAllowance.fish,
      'Κατάλυσις ἰχθύος': FastAllowance.fish,
      'Ημέρα Νηστείας (Κατάλυσις ιχθύος, ελαίου, οίνου, γαλακτοκομικών και '
              'αυγών)':
          FastAllowance.dairyEggsAndFish,
      'Ἀποχή κρέατος': FastAllowance.dairyEggsAndFish,
      'Κατάλυσις Πάντων': FastAllowance.free,
    },
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

/// One GOARCH feed, as a source the tool can build a file from.
class GoarchSource implements CalendarSource {
  const GoarchSource(this.language, this.feed);

  @override
  final String language;

  final Feed feed;

  /// GOARCH publishes the new calendar only.
  @override
  CalendarStyle get style => CalendarStyle.gregorian;

  @override
  String get label => language;

  @override
  String get attribution => feed.url;

  /// The whole feed, every time.
  ///
  /// [from] and [to] are ignored: it arrives as one file whatever is wanted
  /// from it, so there is nothing to narrow the request with.
  @override
  Future<ParsedCalendar> load({
    required String from,
    required String to,
    required bool useCache,
  }) async => parseEvents(
    await fetch(
      feed.url,
      key: '$language.ics',
      label: label,
      useCache: useCache,
    ),
    feed,
  );
}

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

/// Parses VEVENTs into days keyed by ISO date, along with the latest
/// `LAST-MODIFIED` seen anywhere in the feed.
///
/// That timestamp is taken across the whole feed rather than the emitted
/// window, because it answers "has upstream changed at all", which is what
/// decides whether a rebuild is meaningful.
ParsedCalendar parseEvents(String ics, Feed feed) {
  // RFC 5545 folds long lines with CRLF + a single space or tab. Unfold before
  // anything else, or DESCRIPTION arrives in 75-octet fragments.
  final unfolded = ics.replaceAll(_folded, '');

  final result = <String, CalendarDay>{};
  final findings = <Finding>[];
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
    for (final (:line, :kind) in saints.findings) {
      findings.add((date: date, line: line, kind: kind));
    }

    result[date] = CalendarDay(
      date: DateTime.parse(date),
      title: headline.title,
      marks: headline.marks,
      saints: saints.saints,
      fastAllowance: saints.fastAllowance,
      tone: saints.tone,
      eothinon: saints.eothinon,
      epistle: readingFrom(parts[Section.epistle]),
      gospel: readingFrom(parts[Section.gospel]),
      matinsGospel: readingFrom(parts[Section.matinsGospel]),
      oldTestament: readingFrom(parts[Section.oldTestament]),
    );
  }
  return (days: result, sourceUpdatedAt: sourceUpdatedAt, findings: findings);
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
  FastAllowance? fastAllowance,
  int? tone,
  int? eothinon,
  List<({String line, FindingKind kind})> findings,
})
commemorations(String? body, Feed feed) {
  const empty = (
    saints: <String>[],
    fastAllowance: null,
    tone: null,
    eothinon: null,
    findings: <({String line, FindingKind kind})>[],
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
  FastAllowance? allowance;
  final findings = <({String line, FindingKind kind})>[];
  final isFasting = _pattern(feed.fastingPattern);

  for (final paragraph in paragraphs.skip(1)) {
    for (final raw in paragraph.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (feed.tones[line] case final value?) {
        tone = value;
      } else if (feed.eothina[line] case final value?) {
        eothinon = value;
      } else if (feed.fastingRules[line] case final value?) {
        allowance = value;
      } else if (isFasting.hasMatch(line)) {
        // Reads as a fasting rule and is not one we know. This is the whole
        // job fastingPattern still has: telling a rule we failed to map from
        // a line that was never one.
        findings.add((line: line, kind: FindingKind.unmappedFastingRule));
      } else {
        findings.add((line: line, kind: FindingKind.unrecognised));
      }
    }
  }

  return (
    saints: paragraphs.first
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    fastAllowance: allowance,
    tone: tone,
    eothinon: eothinon,
    findings: findings,
  );
}

/// Splits a section body into its citation and the reading text.
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
