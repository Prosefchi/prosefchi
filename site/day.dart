// The day view, compiled to JavaScript by tool/build_site.dart. The one page
// that cannot be generated ahead of time: "today" is a timezone fact, the date
// is unbounded, and the calendar is rebuilt daily.
//
// It fetches the same published JSON the app fetches and resolves it the same
// way `today_screen.dart` does — where the feed states something, prefer it.
// **If one changes, change both.** Dart rather than JavaScript so `toneFor`,
// `eothinonFor` and `fastSeasonFor` are the app's own functions rather than a
// second implementation.

import 'dart:convert';
import 'dart:js_interop';

import 'package:prosefchi/l10n/liturgical_keys.dart';
import 'package:prosefchi/liturgics/fasting.dart';
import 'package:prosefchi/liturgics/octoechos.dart';
import 'package:prosefchi/liturgics/paschalion.dart';
import 'package:prosefchi/models/calendar.dart';
import 'package:web/web.dart' as web;

import 'languages.dart';
import 'strings.dart';

/// From `<body data-root>`. Absolute paths would break under GitHub Pages,
/// which serves a project site from a subdirectory.
late final String _root;

late final String _language;
late final Strings _strings;

/// Null if the fetch failed, which is distinct from a calendar with no entry
/// for the day: one is worth a retry, the other is the feed's window ending.
Calendar? _calendar;

/// The date on screen. Navigation mutates this and re-renders.
late DateTime _date;

void main() async {
  final body = web.document.body!;
  _root = body.getAttribute('data-root') ?? '';
  _language = body.getAttribute('data-lang') ?? 'en';

  // `?lang=` is an alias for the canonical path prefix, since that shape is
  // easy to write by hand.
  if (_redirectForLanguageQuery()) return;

  _date = _dateFromLocation() ?? DateTime.now();

  // Independent, and the first render needs both, so the page waits for the
  // slower rather than the sum.
  final (strings, _) = await (
    loadStrings('${_root}strings.$_language.json'),
    _fetchCalendar(),
  ).wait;
  _strings = strings;

  _render();

  // The back button moves between days, which is what this page does.
  web.window.onpopstate = (web.Event _) {
    _date = _dateFromLocation() ?? DateTime.now();
    _render();
  }.toJS;
}

/// Sends `?lang=xx` to the canonical prefixed path. Returns true if the page
/// is now navigating away and should stop rendering.
bool _redirectForLanguageQuery() {
  final params = web.URLSearchParams(web.window.location.search.toJS);
  final requested = params.get('lang');
  if (requested == null || requested == _language) return false;
  if (!supportedLanguages.contains(requested)) return false;

  params.delete('lang');
  final query = params.toString();
  web.window.location.replace(
    '$_root${prefixFor(requested)}${query.isEmpty ? '' : '?$query'}',
  );
  return true;
}

DateTime? _dateFromLocation() {
  final raw = web.URLSearchParams(web.window.location.search.toJS).get('date');
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  // Drop any time component so the key matches and arithmetic stays on
  // calendar days.
  return DateTime(parsed.year, parsed.month, parsed.day);
}

Future<void> _fetchCalendar() async {
  try {
    final name = Calendar.fileName(_language, style: CalendarStyle.gregorian);
    final response = await web.window.fetch('$_root$name'.toJS).toDart;
    if (!response.ok) return;

    final body = await response.text().toDart;
    _calendar = Calendar.fromJson(
      jsonDecode(body.toDart) as Map<String, dynamic>,
    );
  } on Object {
    // Offline, a bad deploy, a parse failure: one outcome, all retryable.
  }
}

// ---------------------------------------------------------------- rendering

void _render() {
  final host = web.document.querySelector('#day-root')! as web.HTMLElement;
  // Clears the shell's loading placeholder, and the previous day on a re-render.
  host.textContent = '';
  host.className = '';

  // Resolved once and handed down, so the sections cannot disagree.
  final day = _calendar?.forDate(_date);

  host
    ..append(_dateNav())
    ..append(_header(day))
    ..append(_strip(day));

  if (day == null) {
    host.append(_missingDayNotice());
  } else {
    // A single commemoration is the headline again.
    if (day.saints.length > 1) host.append(_commemorations(day.saints));

    // Same order as the app, the Matins gospel last as a separate reading.
    for (final (label, reading) in [
      (_strings['oldTestamentReading'], day.oldTestament),
      (_strings['epistleReading'], day.epistle),
      (_strings['gospelReading'], day.gospel),
      (_strings['matinsGospelReading'], day.matinsGospel),
    ]) {
      if (reading != null) host.append(_reading(label, reading));
    }
  }

  _setDocumentTitle(day?.title);
}

web.HTMLElement _dateNav() {
  final nav = _el('div', className: 'datenav')
    // addDays, never Duration(days: 1), which lands on the wrong calendar day
    // across a daylight-saving change.
    ..append(
      _button('←', () => _goTo(addDays(_date, -1)), label: 'previousDay'),
    )
    ..append(_button('→', () => _goTo(addDays(_date, 1)), label: 'nextDay'));

  // Only worth offering when it would actually move.
  final today = DateTime.now();
  if (Calendar.dateKey(today) != Calendar.dateKey(_date)) {
    nav.append(_button(_strings['today'], () => _goTo(today)));
  }

  final picker = web.document.createElement('input') as web.HTMLInputElement;
  picker
    ..type = 'date'
    ..value = Calendar.dateKey(_date);
  picker.setAttribute('aria-label', _strings['chooseDate']);
  picker.onchange = ((web.Event _) {
    final chosen = DateTime.tryParse(picker.value);
    if (chosen != null) _goTo(chosen);
  }).toJS;
  nav.append(picker);

  return nav;
}

void _goTo(DateTime date) {
  _date = DateTime(date.year, date.month, date.day);
  final isToday = Calendar.dateKey(DateTime.now()) == Calendar.dateKey(_date);
  // Today is the bare URL, so a copied link is not pinned to the day it was
  // copied on.
  final url = isToday ? './' : './?date=${Calendar.dateKey(_date)}';
  web.window.history.pushState(null, '', url);
  _render();
}

/// The date, the commemoration and the pills.
web.HTMLElement _header(CalendarDay? day) {
  final header = _el('section', className: 'day-header');

  header.append(_el('div', className: 'day-date', text: _formatDate(_date)));

  final title = day?.title;
  if (title != null && title.isNotEmpty) {
    header.append(_el('h1', className: 'day-title', text: title));
  }

  // Upstream states the rule on most days it covers and is authoritative
  // there. Past the end of the feed the computed season stands in. Never null,
  // so a day with no fast says so rather than leaving the slot empty — an
  // empty slot is ambiguous between there being no fast and our not knowing,
  // and those are different answers to give someone who came to check.
  final allowance = day?.fastAllowance;
  final fasting = allowance != null
      ? _strings[fastAllowanceKey(allowance)]
      : _computedFasting(_date);

  final pills = _el('div', className: 'pills');
  for (final mark in day?.marks ?? const <DayMark>[]) {
    // The rule in words wins and the fasting markers are dropped, or the day
    // reads as labelled twice. The rank is a different fact, so it stays.
    if (mark != DayMark.majorFeast) continue;
    pills.append(_pill(mark.symbol, _strings[dayMarkKey(mark)]));
  }
  pills.append(_pill('🍽', fasting));
  header.append(pills);

  return header;
}

web.HTMLElement _pill(String symbol, String label) {
  final pill = _el('span', className: 'pill');
  pill
    ..append(_el('span', text: symbol))
    ..append(_el('span', text: label));
  return pill;
}

/// Where the day sits in the year. All three facts are computed, so this is
/// what the page can always say — including after the published feed lapses.
web.HTMLElement _strip(CalendarDay? day) {
  final strip = _el('div', className: 'strip');

  final offset = daysBetween(orthodoxPascha(_date.year), _date);
  strip.append(
    _el(
      'span',
      text: offset >= 0
          ? _strings.plural('daysAfterPascha', offset)
          : _strings.plural('daysUntilPascha', -offset),
    ),
  );

  // Null through Bright Week, where the Octoechos is set aside.
  final tone = day?.tone ?? toneFor(_date);
  if (tone != null) {
    strip.append(_el('span', text: _strings[toneKey(tone)]));
  }

  final eothinon = day?.eothinon ?? eothinonFor(_date);
  strip.append(_el('span', text: _strings.plural('eothinon', eothinon)));

  return strip;
}

web.HTMLElement _commemorations(List<String> saints) {
  final card = _el('section', className: 'card');
  card.append(_el('h2', text: _strings['commemorations']));

  final list = _el('ul', className: 'saints');
  for (final saint in saints) {
    list.append(_el('li', text: saint));
  }
  card.append(list);
  return card;
}

/// A reading, folded away behind its citation as the app folds it.
web.HTMLElement _reading(String label, Reading reading) {
  final details = _el('details', className: 'reading');
  final summary = _el('summary');
  summary
    ..append(_el('span', className: 'reading-label', text: label))
    ..append(_el('span', className: 'reading-ref', text: reading.reference));
  details.append(summary);

  // Absent on the rare entries where upstream gives only a citation.
  final text = reading.text;
  if (text != null) {
    details.append(_el('p', className: 'reading-text', text: text));
  }
  return details;
}

/// Shown when the calendar has no entry for the day. The feed ends on a fixed
/// date and has lapsed for over a year before, so this is a state to sit in.
web.HTMLElement _missingDayNotice() {
  // No calendar is a network problem worth retrying. One that does not reach
  // this date is the feed's window ending, and offering a retry would be a lie.
  final fetchFailed = _calendar == null;

  final notice = _el('div', className: 'notice')
    ..append(
      _el(
        'p',
        text: fetchFailed
            ? _strings['calendarNotDownloaded']
            : _strings['noEntryForDay'],
      ),
    );

  if (fetchFailed) {
    notice.append(
      _button(_strings['retry'], () => _fetchCalendar().then((_) => _render())),
    );
  }
  return notice;
}

/// The fasting rule from the Paschalion, for days upstream does not cover.
String _computedFasting(DateTime date) {
  final season = fastSeasonFor(date);
  if (season != null) return _strings[fastSeasonKey(season)];
  return isFastDay(date) ? _strings['fastDay'] : _strings['noFast'];
}

/// The browser's own date formatting, rather than `package:intl`.
///
/// intl would need its locale data compiled in, which is most of a megabyte
/// for every locale or a build step to trim it. The browser already carries
/// the data, and this is the same shape as the app's
/// `DateFormat.yMMMMEEEEd`.
String _formatDate(DateTime date) =>
    _dateFormat.format(_JSDate(date.year, date.month - 1, date.day));

/// Built once: locale negotiation is expensive, the language cannot change for
/// the life of the page, and this runs twice per date navigation.
final _dateFormat = _IntlDateTimeFormat(
  _language,
  {
        'weekday': 'long',
        'year': 'numeric',
        'month': 'long',
        'day': 'numeric',
      }.jsify()!
      as JSObject,
);

void _setDocumentTitle(String? title) {
  final parts = [
    if (title != null && title.isNotEmpty) title,
    _formatDate(_date),
    _strings['appTitle'],
  ];
  web.document.title = parts.join(' · ');
}

@JS('Intl.DateTimeFormat')
extension type _IntlDateTimeFormat._(JSObject _) implements JSObject {
  external _IntlDateTimeFormat(String locale, JSObject options);
  external String format(JSObject date);
}

@JS('Date')
extension type _JSDate._(JSObject _) implements JSObject {
  external _JSDate(int year, int monthIndex, int day);
}

/// A button. [label] names a string key for `aria-label`, where the visible
/// text is an arrow and says nothing to a screen reader.
web.HTMLButtonElement _button(
  String text,
  void Function() onClick, {
  String? label,
}) {
  final button = _el('button', text: text) as web.HTMLButtonElement;
  if (label != null) button.setAttribute('aria-label', _strings[label]);
  // Not async: a Future cannot cross into JS.
  button.onclick = ((web.Event _) => onClick()).toJS;
  return button;
}

web.HTMLElement _el(String tag, {String? className, String? text}) {
  final element = web.document.createElement(tag) as web.HTMLElement;
  if (className != null) element.className = className;
  // textContent, never innerHTML: commemorations carry apostrophes and
  // ampersands, and there is no reason to hand them to an HTML parser.
  if (text != null) element.textContent = text;
  return element;
}
