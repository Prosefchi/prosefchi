// Builds the web frontend into the directory GitHub Pages is deployed from.
//
//   dart run tool/build_site.dart                 build into build/site
//   dart run tool/build_site.dart --serve         build, fetch a calendar, serve
//   dart run tool/build_site.dart --serve 3000    ...on another port
//   dart run tool/build_site.dart --out DIR       build somewhere else
//   dart run tool/build_site.dart --calendar      fetch the published calendar
//
// The site is deliberately split down one line: **what is static is rendered
// here, and only what cannot be is left to the browser.**
//
//   - The prayers are rendered to HTML now, by `MarkupDocument` — the app's own
//     parser. That is the whole reason this is a Dart script and not Hugo or
//     Jekyll. `res/prayers/*.md` is not Markdown: `>` is a rubric rather than a
//     blockquote, `---` is always a thematic break and never a setext heading,
//     and `**bold**` is meant to ship its asterisks, because pasted liturgical
//     text arrives carrying stray emphasis markers. A CommonMark renderer gets
//     all three wrong, so the site would quietly disagree with the app about
//     what a prayer says. Rendering through markup.dart makes that impossible
//     rather than merely unlikely.
//
//   - The day view is left to the browser, because "today" is a fact about the
//     reader's timezone, the date is unbounded, and the calendar is rebuilt
//     daily. See site/day.dart.
//
// CI builds this and the calendar in separate jobs, merged into one Pages deploy.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// prayer.dart re-exports markup.dart, so the parser and the occasions arrive
// together. The aliases are what make prayer code read in prayer terms — a
// note in a prayer is a rubric.
import 'package:prosefchi/models/calendar.dart' show Calendar;
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/site.dart';

import '../site/languages.dart';
import 'args.dart';

/// Where the site is served from, for canonical and alternate links.
///
/// From lib/models/site.dart, which is also where the app reads it to link to
/// the privacy policy. A canonical naming a host that merely redirects to the
/// real one is a canonical pointing at a redirect.
final _defaultBaseUrl = siteUrl.toString();

/// Published calendars, fetched by `--calendar` for a local preview.
///
/// Deliberately the *published* files rather than a local
/// `tool/build_calendar.dart` run: that downloads ~32 MB of iCal from upstream,
/// which is a great deal to pay to look at a stylesheet change.
///
/// `defaultCalendarBaseUrl`, not [_defaultBaseUrl] — the calendar is fetched
/// from the GitHub Pages host and the site is *served* at the custom domain,
/// and lib/models/site.dart says at length why those two must not be folded
/// into one. Aliasing them here would drag this fetch along behind any future
/// move of the site's own address.
final _publishedCalendars = defaultCalendarBaseUrl;

Future<void> main(List<String> args) async {
  final options = parseArgs(args);
  // Defaults under build/ so a local run lands somewhere already ignored, the
  // same as tool/build_calendar.dart. CI passes --out public and uploads it.
  final outDir = Directory(options['out'] ?? 'build/site');
  final baseUrl = options['base-url'] ?? _defaultBaseUrl;
  final serve = options.containsKey('serve');

  await outDir.create(recursive: true);
  await _build(outDir, baseUrl);

  // A local preview has no calendar beside it unless one is fetched, and the
  // day view without a calendar is exactly the empty state, which is a
  // misleading thing to be looking at while working on the full one.
  if (serve || options.containsKey('calendar')) {
    await _fetchPublishedCalendars(outDir);
  }

  if (serve) {
    _watch(outDir, baseUrl);
    await _serve(outDir, int.tryParse(options['serve'] ?? '') ?? 8000);
  }
}

/// One full build. Everything, every time.
///
/// Nothing here is incremental. The whole site is sixteen pages and one
/// compile, and a rebuild that tried to work out what a given edit affected
/// would be the part that goes wrong — a stale page served after a change is
/// exactly the failure a preview exists to prevent.
Future<void> _build(Directory outDir, String baseUrl) async {
  final shell = await File('site/shell.html').readAsString();
  final strings = await _strings();
  final version = await _version();

  // The compile is a subprocess and much the longest part of a build; nothing
  // that follows reads its output, so it runs alongside rather than in front.
  final compile = _compileDayView(outDir);

  await _copyAssets(outDir, strings);

  // The languages share only immutable inputs, so they are independent.
  final counts = await Future.wait([
    for (final language in supportedLanguages)
      _writeLanguage(
        outDir: outDir,
        shell: shell,
        strings: strings[language]!,
        language: language,
        baseUrl: baseUrl,
        version: version,
      ),
  ]);

  await compile;

  final pages = counts.reduce((a, b) => a + b);
  stdout.writeln('site: wrote $pages pages to ${outDir.path}');
}

// ------------------------------------------------------------------ strings

/// The string table per language: the app's ARB with the site's own labels
/// merged over it.
///
/// The ARB is the app's and stays the single source for everything the two
/// share, so a translation corrected in the app reaches the site on the next
/// deploy with nothing to keep in step.
Future<Map<String, Map<String, String>>> _strings() async {
  final siteOnly =
      jsonDecode(await File('site/extra_strings.json').readAsString())
          as Map<String, dynamic>;

  return {
    for (final language in supportedLanguages)
      language: {
        ..._flatten(
          jsonDecode(await File('lib/l10n/app_$language.arb').readAsString())
              as Map<String, dynamic>,
        ),
        ..._flatten(siteOnly[language] as Map<String, dynamic>? ?? const {}),
      },
  };
}

/// String entries only.
///
/// ARB carries a `@key` metadata object beside each entry, for translators;
/// extra_strings.json carries a `_comment`. Neither is a string to render.
Map<String, String> _flatten(Map<String, dynamic> source) => {
  for (final entry in source.entries)
    if (!entry.key.startsWith('@') &&
        !entry.key.startsWith('_') &&
        entry.value is String)
      entry.key: entry.value as String,
};

// -------------------------------------------------------------------- pages

/// Writes every page for one language, returning how many.
Future<int> _writeLanguage({
  required Directory outDir,
  required String shell,
  required Map<String, String> strings,
  required String language,
  required String baseUrl,
  required String version,
}) async {
  final prefix = prefixFor(language);
  var written = 0;

  Future<void> page(
    String path, {
    required String title,
    required String description,
    required String body,
    String section = '',
    String scripts = '',
  }) async {
    await _writePage(
      outDir: outDir,
      shell: shell,
      strings: strings,
      language: language,
      baseUrl: baseUrl,
      path: path,
      title: title,
      description: description,
      body: body,
      section: section,
      scripts: scripts,
    );
    written++;
  }

  // The day view.
  await page(
    prefix,
    title: strings['today']!,
    description: strings['attribution']!,
    section: 'day',
    body: _dayBody(strings),
    // `defer` so the parser is not blocked; the script only touches the DOM
    // once it has fetched anyway.
    scripts: '<script defer src="${_rootFor(prefix)}day.js"></script>',
  );

  // The prayers, rendered now rather than in the browser.
  final documents = <PrayerOccasion, PrayerSet>{};
  for (final occasion in PrayerOccasion.values) {
    documents[occasion] = MarkupDocument.parse(
      await File(occasion.assetPath(language)).readAsString(),
    );
  }

  await page(
    '${prefix}prayers/',
    title: strings['prayers']!,
    description: strings['prayersIntro']!,
    section: 'prayers',
    body: _prayerIndexBody(strings, documents),
  );

  for (final entry in documents.entries) {
    final document = entry.value;
    // A rule with no text yet is still listed, so its absence is visible, but
    // it gets no page of its own: a heading over nothing promises more than
    // the greyed-out row on the index does.
    if (!document.hasContent) continue;

    await page(
      '${prefix}prayers/${entry.key.slug}/',
      title: document.title.isEmpty
          ? strings[_occasionKey(entry.key)]!
          : document.title,
      description: strings['prayersIntro']!,
      section: 'prayers',
      // `doc` is how anything read at length is set and `prayer` only adds the
      // serif, so a prayer is both rather than a class of its own.
      body: _documentHtml(document, tag: 'article', className: 'doc prayer'),
    );
  }

  // The about page, with the download advert at the top of it.
  //
  // The advert is the one authored document that carries HTML, so it is the one
  // that can name an image, and `{{root}}` in it means what it means in the
  // shell: the way back up to the site root, which is one directory from the
  // English about page and two from the Greek.
  final about = '${prefix}about/';
  await page(
    about,
    title: strings['about']!,
    description: strings['aboutSiteVersion']!,
    section: 'about',
    body: _aboutBody(
      strings,
      MarkupDocument.parse(
        (await File(
          'site/download_$language.md',
        ).readAsString()).replaceAll('{{root}}', _rootFor(about)),
      ),
      version,
      privacyHref: '${_rootFor(about)}${privacyPagePath(language)}',
    ),
  );

  // The privacy policy, under the about page that links to it.
  //
  // Authored at the repository root rather than in site/, because GitHub and
  // Google Play both look for a PRIVACY.md there, and rendered here so the one
  // document serves the repository, the store listing and the app's own link.
  // It is `about` in the nav, not a section of its own: a policy is something
  // to be able to find rather than somewhere to be sent.
  await page(
    privacyPagePath(language),
    title: strings['privacyPolicy']!,
    description: strings['privacyPolicySubtitle']!,
    section: 'about',
    body: _documentHtml(
      MarkupDocument.parse(await File(privacySource(language)).readAsString()),
      tag: 'article',
      className: 'doc',
    ),
  );

  return written;
}

/// The authored privacy policy for [language].
///
/// English keeps the bare `PRIVACY.md`, which is where GitHub and Google Play
/// look, and every translation sits beside it under its code — the same shape
/// `prefixFor` gives the site's own paths.
///
/// Public so test/tool/ can hold the files to existing and parsing.
String privacySource(String language) => language == supportedLanguages.first
    ? 'PRIVACY.md'
    : 'PRIVACY.$language.md';

/// Fills the shell and writes it at [path], which is a directory path ending in
/// `/` (or empty for the site root).
///
/// Directories with an `index.html` rather than `name.html`, so every URL on
/// the site is a clean path that GitHub Pages serves with a 200. The
/// alternative — a 404.html catch-all doing client-side routing — serves real
/// pages under an HTTP error status, which search engines take at their word.
Future<void> _writePage({
  required Directory outDir,
  required String shell,
  required Map<String, String> strings,
  required String language,
  required String baseUrl,
  required String path,
  required String title,
  required String description,
  required String body,
  required String section,
  required String scripts,
}) async {
  final root = _rootFor(path);

  // The page's path with its language prefix off, which is what every
  // translation of it has in common.
  final shared = withoutLanguage(path);

  String current(bool isIt) => isIt ? ' aria-current="page"' : '';

  final slots = {
    // Escaped: text, most of it from a translation file, where a stray `&` or
    // quote must not break the page it lands in.
    'lang': _Slot.text(language),
    'root': _Slot.text(root),
    'langPath': _Slot.text(prefixFor(language)),
    'title': _Slot.text('$title · ${strings['appTitle']}'),
    'description': _Slot.text(description),
    'canonical': _Slot.text('$baseUrl$path'),
    'appTitle': _Slot.text(strings['appTitle']!),
    'today': _Slot.text(strings['today']!),
    'prayers': _Slot.text(strings['prayers']!),
    'about': _Slot.text(strings['about']!),
    'navLabel': _Slot.text(strings['navLabel']!),
    'languageLabel': _Slot.text(strings['languageLabel']!),
    'skipToContent': _Slot.text(strings['skipToContent']!),
    'attribution': _Slot.text(strings['attribution']!),
    'sourceCode': _Slot.text(strings['sourceCode']!),

    // Verbatim: markup this file generated.
    'body': _Slot.markup(body),
    'scripts': _Slot.markup(scripts),
    'dayCurrent': _Slot.markup(current(section == 'day')),
    'prayersCurrent': _Slot.markup(current(section == 'prayers')),
    'aboutCurrent': _Slot.markup(current(section == 'about')),
    // One entry per language rather than a pair of named ones, so the shell
    // stops knowing how many languages there are and adding a third needs no
    // edit here or in it.
    'alternates': _Slot.markup(_alternates(baseUrl, shared)),
    'languageLinks': _Slot.markup(
      _languageLinks(root, shared, language, strings),
    ),
  };

  // Every placeholder in the shell must be filled, and an unknown one fails
  // the build. Left to a per-key replaceAll, a placeholder added to the shell
  // and forgotten here would ship the literal `{{whatever}}` to production.
  final html = shell.replaceAllMapped(_placeholder, (match) {
    final name = match[1]!;
    final slot = slots[name];
    if (slot == null) {
      throw StateError('site: shell.html has no value for {{$name}}');
    }
    return slot.raw ? slot.value : _esc(slot.value);
  });

  final file = File('${outDir.path}/${path}index.html');
  await file.parent.create(recursive: true);
  await file.writeAsString(html);
}

/// The relative path from a page at [path] back to the site root.
///
/// Absolute paths would be wrong: GitHub Pages serves a project site under
/// /prosefchi/, not /. A relative root also lets the built site be opened
/// straight off disk.
String _rootFor(String path) {
  final depth = path.split('/').where((part) => part.isNotEmpty).length;
  return depth == 0 ? '' : '../' * depth;
}

final _placeholder = RegExp(r'\{\{(\w+)\}\}');

/// One value bound for the shell, and whether it is markup or text.
///
/// Whether something needs escaping is a property of the value, so it is
/// carried with the value. A separate list of which names are markup is a
/// second thing to keep in step, and forgetting to add a name to it shows up
/// as visible `&lt;span&gt;` on a deployed page.
class _Slot {
  const _Slot.text(this.value) : raw = false;
  const _Slot.markup(this.value) : raw = true;

  final String value;
  final bool raw;
}

/// The `hreflang` links: this page in every language it exists in.
String _alternates(String baseUrl, String shared) => [
  for (final language in supportedLanguages)
    '<link rel="alternate" hreflang="$language" '
        'href="${_esc('$baseUrl${prefixFor(language)}$shared')}" />',
].join('\n    ');

/// The language switcher: this page in every language, the current one marked.
String _languageLinks(
  String root,
  String shared,
  String current,
  Map<String, String> strings,
) => [
  for (final language in supportedLanguages)
    '<a href="${_esc('$root${prefixFor(language)}$shared')}" '
        'lang="$language"'
        '${language == current ? ' aria-current="true"' : ''}>'
        // The label a language calls itself, so it is readable whichever
        // language the page is currently in.
        '${_esc(strings['languageShortName_$language'] ?? language.toUpperCase())}'
        '</a>',
].join('\n        ');

/// Escapes text for HTML.
///
/// `dart:convert`'s escaper rather than a hand-rolled one, so the ordering is
/// right by construction — `&` before the replacements that introduce more of
/// them.
///
/// The mode is stated rather than taking the `unknown` default, which also
/// escapes `/` and `'`. Both are valid and both are wrong here: every path on
/// the site would become `&#47;`-noise, and liturgical English is full of
/// apostrophes — "for your name's sake" would render its source as `&#39;`
/// through every prayer. Neither character is dangerous in element text, and
/// every attribute this file emits is double-quoted, which `escapeQuot`
/// covers.
const _escape = HtmlEscape(
  HtmlEscapeMode(name: 'prosefchi', escapeLtGt: true, escapeQuot: true),
);

String _esc(String text) => _escape.convert(text);

// --------------------------------------------------------------- page bodies

/// The day view is a shell the compiled Dart fills in.
String _dayBody(Map<String, String> strings) =>
    '<div id="day-root" class="loading">${_esc(strings['loading']!)}</div>\n'
    '    <noscript>\n'
    '      <p class="notice">${_esc(strings['noScript']!)}</p>\n'
    '    </noscript>';

String _prayerIndexBody(
  Map<String, String> strings,
  Map<PrayerOccasion, PrayerSet> documents,
) {
  final out = StringBuffer()
    ..writeln('<p>${_esc(strings['prayersIntro']!)}</p>')
    ..writeln('<div class="prayer-list">');

  for (final occasion in PrayerOccasion.values) {
    // A heading wherever the group changes. `startsGroup` is the app's own,
    // so the three lists cannot disagree about where the breaks fall; it
    // leans on each group staying contiguous in the enum, which a test pins.
    if (occasion.startsGroup) {
      out.writeln('  <h2>${_esc(strings[_groupKey(occasion.group)]!)}</h2>');
    }

    final name = _esc(strings[_occasionKey(occasion)]!);
    if (documents[occasion]!.hasContent) {
      out.writeln('  <a href="${occasion.slug}/">$name</a>');
    } else {
      // Listed but not linked, so a rule whose text is still awaited is
      // visibly absent rather than silently missing.
      out.writeln(
        '  <a aria-disabled="true">$name'
        '<span class="unavailable">'
        '${_esc(strings['prayerNotAvailable']!)}</span></a>',
      );
    }
  }

  out.writeln('</div>');
  return out.toString();
}

/// A parsed document as HTML, titled and wrapped.
///
/// Nothing is appended to send the reader back: the header carries the way to
/// the rest of the site on every page, and a second link at the bottom of a
/// text as long as a prayer rule is furniture rather than navigation.
String _documentHtml(
  MarkupDocument document, {
  required String tag,
  required String className,
}) {
  final out = StringBuffer()..writeln('<$tag class="$className">');

  if (document.title.isNotEmpty) {
    out.writeln('  <h1>${_esc(document.title)}</h1>');
  }
  out
    ..write(_renderBlocks(document.blocks))
    ..writeln('</$tag>');
  return out.toString();
}

/// The about page: what the app is and where to get it, then the same three
/// facts the app's own about section carries — the source, the version and the
/// licence.
///
/// The download advert on top is authored markdown rather than markup in here,
/// so the pitch can be rewritten without touching the build, and it goes
/// through the same parser as a prayer so it renders the same way.
String _aboutBody(
  Map<String, String> strings,
  MarkupDocument download,
  String version, {
  required String privacyHref,
}) {
  final out = StringBuffer()
    ..write(_documentHtml(download, tag: 'section', className: 'download'))
    ..writeln('<h2 class="about-heading">${_esc(strings['about']!)}</h2>')
    ..writeln('<div class="rows">');

  // Mirrors lib/screens/about_section.dart, in its order. The repository opens
  // in a new tab for the reason the app opens it in an external browser rather
  // than the in-app one: it is somewhere to go and act, not to read and come
  // back from.
  out
    ..writeln(
      _row(
        title: strings['sourceCode']!,
        subtitle: strings['sourceCodeSubtitle']!,
        href: 'https://github.com/Prosefchi/prosefchi',
      ),
    )
    // The one row that stays on this site, so it is an ordinary link: no new
    // tab, and no arrow, since there is nothing to warn anyone they are
    // leaving. Resolved from the page's own root rather than written as
    // `privacy/`, which is only right while the policy sits directly under the
    // about page — moving `privacyPath` would otherwise leave this link behind
    // on a 404 that nothing checks.
    ..writeln(
      _row(
        title: strings['privacyPolicy']!,
        subtitle: strings['privacyPolicySubtitle']!,
        href: privacyHref,
      ),
    )
    ..writeln(
      _row(
        title: strings['appVersion']!,
        // Read from pubspec.yaml at build time, exactly as the app reads it back
        // out of the bundle: one source, so the two cannot disagree about which
        // version this is.
        subtitle: version,
      ),
    )
    ..writeln(
      _row(
        title: strings['openSourceLicences']!,
        subtitle: strings['licenceName']!,
        href: 'https://github.com/Prosefchi/prosefchi/blob/master/LICENSE',
      ),
    )
    ..writeln('</div>')
    ..writeln('<p class="fineprint">${_esc(strings['calendarNotice']!)}</p>');

  return out.toString();
}

/// One about row: a title over a subtitle, linked or not.
///
/// Whether the link leaves the site is read off [href] rather than passed in
/// beside it. Every off-site link the generator emits is absolute and every
/// on-site one is relative, so the flag could only ever restate what the URL
/// already says — and the row that gets it wrong is the *next* same-site one
/// somebody adds, which would open in a new tab with an "outside" arrow on it.
/// The stylesheet hangs the ↗ off the `target` this sets rather than off a
/// class of its own, so the two cannot disagree either.
String _row({required String title, required String subtitle, String? href}) {
  final content =
      '<span class="row-title">${_esc(title)}</span>'
      '<span class="row-sub">${_esc(subtitle)}</span>';

  if (href == null) return '  <div class="row">$content</div>';

  final target = Uri.parse(href).hasScheme
      ? ' target="_blank" rel="noopener"'
      : '';
  return '  <a class="row" href="${_esc(href)}"$target>$content</a>';
}

/// The app version, from the one place that states it.
///
/// `pubspec.yaml`'s `version:` and nothing else — the same string
/// .github/workflows/release.yml refuses to build a disagreeing tag against.
/// Any build number after `+` is dropped: it means nothing on a website.
Future<String> _version() async {
  for (final line in await File('pubspec.yaml').readAsLines()) {
    final match = _versionLine.firstMatch(line);
    if (match != null) return match[1]!.split('+').first;
  }
  throw StateError('site: no version: in pubspec.yaml');
}

/// Anchored at the start of the line, so it cannot match a nested key.
final _versionLine = RegExp(r'^version:\s*(\S+)');

/// Renders parsed blocks to HTML.
///
/// The one place the site turns authored prayer text into markup, and it works
/// from `MarkupDocument`'s output rather than from the source, so the site and
/// the app agree by construction about what a `>` line is.
String _renderBlocks(List<MarkupBlock> blocks) {
  final out = StringBuffer();
  for (final block in blocks) {
    switch (block) {
      case MarkupHeading(:final text):
        out.writeln('  <h2>${_esc(text)}</h2>');
      case MarkupDivider():
        out.writeln('  <hr />');
      // A rubric is an instruction to the reader, not words to be said aloud.
      // It is not a blockquote and must not be rendered as one — reading one
      // out as though it were the prayer is the confusion this prevents.
      case MarkupNote(:final spans):
        out.writeln('  <p class="rubric">${_renderSpans(spans)}</p>');
      case MarkupText(:final spans):
        out.writeln('  <p>${_renderSpans(spans)}</p>');
      // Classed like a rubric, and styled off that class rather than off the
      // document around it: every kind of document can hold a list, and a
      // browser's own list styling is nothing like the rest of the page.
      case MarkupList(:final ordered, :final items):
        final tag = ordered ? 'ol' : 'ul';
        out.writeln('  <$tag class="items">');
        for (final item in items) {
          out.writeln('    <li>${_renderSpans(item.spans)}</li>');
        }
        out.writeln('  </$tag>');
      // Verbatim, and outside a <p>: a run of HTML is block-level markup the
      // author wrote for this renderer, and wrapping a <div> in a paragraph
      // would close the paragraph early and leave a stray tag behind.
      case MarkupHtmlBlock(:final html):
        out.writeln(html);
    }
  }
  return out.toString();
}

String _renderSpans(List<MarkupSpan> spans) {
  final out = StringBuffer();
  for (final span in spans) {
    switch (span) {
      case MarkupLink(:final text, :final url):
        // A source link leaves the site, so it says so the way the app does by
        // opening a browser view over itself: a new tab, rather than replacing
        // the prayer someone is in the middle of.
        out.write(
          '<a href="${_esc(url)}" target="_blank" rel="noopener">'
          '${_esc(text)}</a>',
        );
      // Passed through unescaped — the whole point of a tag reaching here. It
      // is authored content in this repository, not anything a reader supplies,
      // so there is no untrusted input to escape.
      case MarkupHtml(:final html):
        out.write(html);
      case MarkupPlain(:final text):
        out.write(_esc(text));
    }
  }
  return out.toString();
}

/// The ARB key naming [occasion], derived rather than mapped.
///
/// `before_communion` becomes `prayerBeforeCommunion`. A hand-written map would
/// be a third copy of the same switch that `lib/l10n/occasion_labels.dart`
/// already holds for the app, and one that could silently fall out of step with
/// the enum; this cannot.
String _occasionKey(PrayerOccasion occasion) =>
    'prayer${_camel(occasion.slug)}';

String _groupKey(PrayerGroup group) => 'prayerGroup${_camel(group.name)}';

String _camel(String slug) => slug
    .split('_')
    .map((part) => part[0].toUpperCase() + part.substring(1))
    .join();

// ------------------------------------------------------------------- assets

/// Compiles the day view to JavaScript.
Future<void> _compileDayView(Directory outDir) async {
  final result = await Process.run('dart', [
    'compile',
    'js',
    '-O2',
    'site/day.dart',
    '-o',
    '${outDir.path}/day.js',
  ]);

  if (result.exitCode != 0) {
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    throw StateError('site: compiling site/day.dart failed');
  }

  // Build artefacts of the compile, neither served nor useful in the deploy.
  // `.deps` in particular lists absolute paths from the build machine.
  for (final name in ['day.js.map', 'day.js.deps']) {
    final artefact = File('${outDir.path}/$name');
    if (artefact.existsSync()) await artefact.delete();
  }

  final size = await File('${outDir.path}/day.js').length();
  stdout.writeln('site: day.js is ${(size / 1024).toStringAsFixed(0)} KB');
}

Future<void> _copyAssets(
  Directory outDir,
  Map<String, Map<String, String>> strings,
) async {
  await File('site/style.css').copy('${outDir.path}/style.css');

  for (final language in supportedLanguages) {
    await File(
      '${outDir.path}/strings.$language.json',
    ).writeAsString(jsonEncode(strings[language]));
  }

  // The launcher artwork, for the larger icon slots. Not fatal if it is
  // missing: it is a build input for the icon generator rather than something
  // the app ships, so a checkout without it should still produce a site.
  final icon = File('assets/icon/icon.png');
  if (icon.existsSync()) {
    await icon.copy('${outDir.path}/icon.png');
  } else {
    stdout.writeln('site: assets/icon/icon.png missing, no apple-touch icon');
  }

  // The tab icon: the app's notification cross on the brand red. A checked-in
  // asset rather than something composited here, since it changes only when
  // the artwork does. site/icon.svg explains why it is plated.
  await File('site/icon.svg').copy('${outDir.path}/icon.svg');

  await _copyTree(Directory('site/img'), Directory('${outDir.path}/img'));
}

/// Copies [from] into [to], directories and all.
///
/// Whatever is in `site/img/` is published, rather than a list here naming each
/// file: an image added to the advert should need editing only the document
/// that shows it. The screenshots are also what the README displays, which is
/// why they live under `site/` rather than in a directory of their own.
Future<void> _copyTree(Directory from, Directory to) async {
  if (!from.existsSync()) return;

  await to.create(recursive: true);
  await for (final entity in from.list()) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    if (entity is Directory) {
      await _copyTree(entity, Directory('${to.path}/$name'));
    } else if (entity is File) {
      await entity.copy('${to.path}/$name');
    }
  }
}

/// Downloads the published calendars, for a local preview.
Future<void> _fetchPublishedCalendars(Directory outDir) async {
  final client = HttpClient();
  try {
    for (final language in supportedLanguages) {
      final file = File('${outDir.path}/${Calendar.fileName(language)}');
      if (file.existsSync()) continue;

      final name = Calendar.fileName(language);
      final request = await client.getUrl(_publishedCalendars.resolve(name));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        stdout.writeln('site: could not fetch $name (${response.statusCode})');
        continue;
      }
      await response.pipe(file.openWrite());
      stdout.writeln('site: fetched $name');
    }
  } on Object catch (error) {
    // A preview without a calendar still renders; the day view shows its empty
    // state, which is a real state worth being able to look at.
    stdout.writeln('site: could not fetch calendars ($error)');
  } finally {
    client.close();
  }
}

// ------------------------------------------------------------------- watch

/// Bumped by every successful rebuild. The preview page polls it and reloads
/// when it moves, which is what makes an edit show up without a manual
/// refresh.
var _buildSerial = 0;

/// Everything a page on the site is built from.
///
/// `lib/` is in here because site/day.dart compiles the liturgics in, so a fix
/// to the Paschalion has to reach the preview too.
// PRIVACY*.md by name rather than the repository root, which would sweep in
// build output and .git. They are build inputs like any authored document, so
// a policy saved during a preview should reload the page it is rendered on.
const _watched = [
  'site',
  'res/prayers',
  'lib',
  'pubspec.yaml',
  'PRIVACY.md',
  'PRIVACY.el.md',
];

/// Rebuilds whenever a source file changes.
void _watch(Directory outDir, String baseUrl) {
  Timer? debounce;
  var building = false;
  var again = false;

  Future<void> rebuild() async {
    // A save landing mid-build is noted and served after it, rather than
    // dropped — dropping one leaves the preview stale until the next save,
    // which is the one thing a watcher must not do.
    if (building) {
      again = true;
      return;
    }

    building = true;
    do {
      again = false;
      try {
        await _build(outDir, baseUrl);
        _buildSerial++;
      } on Object catch (error) {
        // A syntax error while editing is ordinary. Report it and keep
        // watching; the previous build stays served, so the page in the
        // browser is the last one that worked rather than a broken one.
        stderr.writeln('site: rebuild failed ($error)');
      }
    } while (again);
    building = false;
  }

  void schedule(String path) {
    // Editors write a file several times to save it once — a temporary, a
    // rename, a mode change — and the compile is the better part of a second,
    // so a rebuild per event would queue up behind itself.
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 150), rebuild);
  }

  for (final path in _watched) {
    final entity = FileSystemEntity.isDirectorySync(path)
        ? Directory(path)
        : File(path);
    if (!entity.existsSync()) continue;

    entity.watch(recursive: entity is Directory).listen((event) {
      // The output directory is inside neither of these, but a generated
      // localization under lib/l10n/ is written by the Flutter build and would
      // otherwise rebuild the site for no reason.
      if (event.path.contains('app_localizations')) return;
      schedule(event.path);
    });
  }

  stdout.writeln('site: watching ${_watched.join(', ')}');
}

/// Injected into every HTML page the preview server sends.
///
/// Only by the preview server, never written into the built output: the
/// deployed site must not poll anything.
const _reloadScript = '''
<script>
  // Polls the preview server's build serial and reloads when it moves.
  (function () {
    var current = null;
    setInterval(function () {
      fetch('/__build', { cache: 'no-store' })
        .then(function (r) { return r.text(); })
        .then(function (serial) {
          if (current === null) current = serial;
          else if (serial !== current) location.reload();
        })
        .catch(function () {});
    }, 500);
  })();
</script>
''';

// -------------------------------------------------------------------- serve

const _contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  // Without this the favicon is served as a byte stream and the browser
  // declines to render it, which reads as "the icon is broken" rather than as
  // a missing line here.
  '.svg': 'image/svg+xml',
};

/// A static file server for previewing the built site.
///
/// Only ever a preview. GitHub Pages serves the deployed site, so nothing here
/// needs to match its behaviour beyond resolving a directory to its index.
Future<void> _serve(Directory outDir, int port) async {
  final root = outDir.absolute.path;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);

  stdout.writeln('site: serving $root at http://localhost:$port/');
  stdout.writeln('site: ctrl-c to stop');

  await for (final request in server) {
    var path = Uri.decodeComponent(request.uri.path);

    // What the injected reload script polls.
    if (path == '/__build') {
      request.response
        ..headers.set(HttpHeaders.contentTypeHeader, 'text/plain')
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..write(_buildSerial);
      await request.response.close();
      continue;
    }

    if (path.endsWith('/')) path = '${path}index.html';

    final file = File('$root$path');
    // Refuse anything that escapes the output directory. A preview server on
    // loopback is not a threat model, but serving the whole filesystem by
    // accident is still worth one line to prevent.
    if (!file.absolute.path.startsWith(root) || !file.existsSync()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.html
        ..write('<h1>404</h1><p>$path</p>');
      await request.response.close();
      continue;
    }

    final extension = path.contains('.')
        ? path.substring(path.lastIndexOf('.'))
        : '';
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      _contentTypes[extension] ?? 'application/octet-stream',
    );
    // A preview is looked at while editing, so nothing may be cached.
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    // The reload script is injected on the way out rather than built into the
    // page, so the deployed site never carries it.
    if (extension == '.html') {
      final html = await file.readAsString();
      request.response.write(
        html.replaceFirst('</body>', '$_reloadScript</body>'),
      );
      await request.response.close();
      continue;
    }

    await file.openRead().pipe(request.response);
  }
}
