// Builds the web frontend into the directory GitHub Pages is deployed from.
//
//   dart run tool/build_site.dart                 build into build/site
//   dart run tool/build_site.dart --serve         build, fetch a calendar, serve
//   dart run tool/build_site.dart --serve 3000    ...on another port
//   dart run tool/build_site.dart --out DIR       build somewhere else
//   dart run tool/build_site.dart --calendar      fetch the published calendar
//
// What is static is rendered here, and only what cannot be is left to the
// browser: the prayers now, through the app's own `MarkupDocument`, and the day
// view in site/day.dart, since "today" is a timezone fact. CLAUDE.md has why
// that line falls there and why this is not Hugo.
//
// The preview turns the service worker off, so to look at the installed thing,
// build without --serve and serve the output with any static server.
//
// CI builds this and the calendar in separate jobs, merged into one Pages deploy.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// prayer.dart re-exports markup.dart, so the parser and the occasions arrive
// together. The aliases are what make prayer code read in prayer terms — a
// note in a prayer is a rubric.
import 'package:prosefchi/models/calendar.dart' show Calendar, CalendarStyle;
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/site.dart';

import '../site/languages.dart';
import 'args.dart';

Future<void> main(List<String> args) async {
  final options = parseArgs(args);
  // Under build/ so a local run lands somewhere already ignored. CI passes
  // --out public and uploads it.
  final outDir = Directory(options['out'] ?? 'build/site');
  // Where the site is served from, for canonical and alternate links.
  final baseUrl = options['base-url'] ?? siteUrl.toString();
  final serve = options.containsKey('serve');

  await outDir.create(recursive: true);
  await _build(outDir, baseUrl);

  // Without one the day view shows its empty state, which is a misleading
  // thing to be looking at while working on the full one.
  if (serve || options.containsKey('calendar')) {
    await _fetchPublishedCalendars(outDir);
  }

  if (serve) {
    _watch(outDir, baseUrl);
    await _serve(outDir, int.tryParse(options['serve'] ?? '') ?? 8000);
  }
}

/// One full build, everything every time. Sixteen pages and one compile, and a
/// stale page served after a change is the failure a preview exists to prevent.
Future<void> _build(Directory outDir, String baseUrl) async {
  final shell = await File('site/shell.html').readAsString();
  final strings = await siteStrings();
  final version = await _version();

  // Much the longest part of a build, and nothing below reads its output.
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

  // Last, because it lists what everything above wrote.
  await _writeServiceWorker(outDir);

  final pages = counts.reduce((a, b) => a + b);
  stdout.writeln('site: wrote $pages pages to ${outDir.path}');
}

// ------------------------------------------------------------------ strings

/// The app's ARB with the site's own labels merged over it, so a translation
/// corrected in the app reaches the site with nothing to keep in step.
///
/// Public so test/tool/ builds a manifest from the real strings rather than a
/// table beside the test, which would agree with itself.
Future<Map<String, Map<String, String>>> siteStrings() async {
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
    // Listed on the index but given no page: a heading over nothing promises
    // more than a greyed-out row does.
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

  // The download advert is the one authored document carrying HTML, so the one
  // that can name an image. `{{root}}` in it is the shell's, resolved before
  // parsing: one directory up in English, two in Greek.
  final about = '${prefix}about/';
  await page(
    about,
    title: strings['about']!,
    description: strings['aboutSiteVersion']!,
    section: 'about',
    scripts: _installScript,
    body: _aboutBody(
      strings,
      MarkupDocument.parse(
        (await File(
          downloadSource(language),
        ).readAsString()).replaceAll('{{root}}', _rootFor(about)),
      ),
      version,
      privacyHref: '${_rootFor(about)}${privacyPagePath(language)}',
    ),
  );

  // The privacy policy, under the about page that links to it.
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

String downloadSource(String language) => 'site/download_$language.md';

/// The web app manifest for [language], written into that language's own
/// directory so every path in it can be relative.
///
/// No `id`: it resolves against the origin rather than against this file, so it
/// would be the one value here that has to know whether the site is deployed at
/// `/` or at `/prosefchi/`. Left out, a browser derives it from `start_url`.
String webManifest({
  required Map<String, String> strings,
  required String language,
}) {
  final root = _rootFor(prefixFor(language));

  return const JsonEncoder.withIndent('  ').convert({
    'name': strings['appTitle'],
    'short_name': strings['appTitle'],
    'description': strings['appDescription'],
    'lang': language,
    'dir': 'ltr',
    // This language's directory; the site root, so the language switcher stays
    // inside the installed app.
    'start_url': '.',
    'scope': root.isEmpty ? '.' : root,
    'display': 'standalone',
    'theme_color': '#7b1113',
    // Paints the splash before any CSS loads, so it cannot follow the theme.
    'background_color': '#fbf8f6',
    'icons': [
      for (final icon in _icons)
        {
          'src': '$root${icon.file}',
          'sizes': '${icon.size}x${icon.size}',
          'type': 'image/png',
          'purpose': icon.purpose,
        },
    ],
  });
}

/// The icons the manifest names, checked in under `site/`. CLAUDE.md carries
/// the commands they are cut with.
///
/// Both maskable sizes are needed: offered only a 512, Chrome fell back to an
/// `any` icon and masked the flag, cutting its firesteels. `page` marks the
/// ones the pages reference; the rest a browser fetches at install.
const _icons = [
  (file: 'icon-192.png', size: 192, purpose: 'any', page: true),
  (file: 'icon-512.png', size: 512, purpose: 'any', page: false),
  (file: 'icon-maskable-192.png', size: 192, purpose: 'maskable', page: false),
  (file: 'icon-maskable-512.png', size: 512, purpose: 'maskable', page: false),
];

/// Public so test/tool/ can hold each to existing.
final iconFiles = [for (final icon in _icons) icon.file];

final _manifestOnlyIcons = {
  for (final icon in _icons)
    if (!icon.page) icon.file,
};

/// Keep `RUNTIME` in site/sw.js in step: the preview's cleanup filters on this,
/// and the precache name's other half is a digest it cannot know.
const _cachePrefix = 'prosefchi-';

/// English keeps the bare `PRIVACY.md`, where GitHub and Google Play look.
String privacySource(String language) => language == supportedLanguages.first
    ? 'PRIVACY.md'
    : 'PRIVACY.$language.md';

/// Fills the shell and writes it at [path], which is a directory path ending in
/// `/` (or empty for the site root).
///
/// Directories with an `index.html`, so every URL is a clean path served with
/// a 200. The 404.html catch-all trick serves real pages under an HTTP error
/// status, which search engines take at their word.
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
    'swRegister': _Slot.markup(_registerScript),
    'dayCurrent': _Slot.markup(current(section == 'day')),
    'prayersCurrent': _Slot.markup(current(section == 'prayers')),
    'aboutCurrent': _Slot.markup(current(section == 'about')),
    // One entry per language, so the shell need not know how many there are.
    'alternates': _Slot.markup(_alternates(baseUrl, shared)),
    'languageLinks': _Slot.markup(
      _languageLinks(root, shared, language, strings),
    ),
  };

  // The slot decides the escaping, _fill does the substitution.
  final html = _fill(shell, {
    for (final slot in slots.entries)
      slot.key: slot.value.raw ? slot.value.value : _esc(slot.value.value),
  });

  final file = File('${outDir.path}/${path}index.html');
  await file.parent.create(recursive: true);
  await file.writeAsString(html);
}

/// The relative path from a page at [path] back to the site root. Absolute
/// would be wrong: Pages serves a project site under /prosefchi/, not /.
String _rootFor(String path) {
  final depth = path.split('/').where((part) => part.isNotEmpty).length;
  return depth == 0 ? '' : '../' * depth;
}

final _placeholder = RegExp(r'\{\{(\w+)\}\}');

/// One value bound for the shell. Escaping is carried with the value rather
/// than in a list of which names are markup, which would be a second thing to
/// keep in step and fails as visible `&lt;span&gt;` on a deployed page.
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

/// The mode is stated rather than taking the `unknown` default, which also
/// escapes `/` and `'`: every path would become `&#47;`-noise, and "for your
/// name's sake" would render its source as `&#39;` through every prayer.
/// Neither is dangerous in element text, and every attribute here is
/// double-quoted.
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
    // `startsGroup` is the app's own, so the three lists cannot disagree.
    if (occasion.startsGroup) {
      out.writeln('  <h2>${_esc(strings[_groupKey(occasion.group)]!)}</h2>');
    }

    final name = _esc(strings[_occasionKey(occasion)]!);
    if (documents[occasion]!.hasContent) {
      out.writeln('  <a href="${occasion.slug}/">$name</a>');
    } else {
      // Listed but not linked, so an awaited rule is visibly absent.
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

/// The download advert, then the same rows the app's own about section carries.
/// The advert is authored rather than built here, and goes through the same
/// parser as a prayer.
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

  // Mirrors lib/screens/about_section.dart, in its order.
  out
    ..writeln(
      _row(
        title: strings['sourceCode']!,
        subtitle: strings['sourceCodeSubtitle']!,
        href: 'https://github.com/Prosefchi/prosefchi',
      ),
    )
    // The one row that stays on this site, so it is an ordinary link.
    ..writeln(
      _row(
        title: strings['privacyPolicy']!,
        subtitle: strings['privacyPolicySubtitle']!,
        href: privacyHref,
      ),
    )
    ..writeln(_row(title: strings['appVersion']!, subtitle: version))
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

/// An absolute [href] leaves the site and opens in a new tab; a relative one
/// stays. The stylesheet hangs the ↗ off that `target`.
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

/// `pubspec.yaml`'s `version:` and nothing else, which is the string
/// release.yml refuses to build a disagreeing tag against. Any `+build` is
/// dropped: it means nothing on a website.
Future<String> _version() async {
  for (final line in await File('pubspec.yaml').readAsLines()) {
    final match = _versionLine.firstMatch(line);
    if (match != null) return match[1]!.split('+').first;
  }
  throw StateError('site: no version: in pubspec.yaml');
}

/// Anchored at the start of the line, so it cannot match a nested key.
final _versionLine = RegExp(r'^version:\s*(\S+)');

/// Works from `MarkupDocument`'s output rather than the source, so the site and
/// the app agree by construction about what a `>` line is.
String _renderBlocks(List<MarkupBlock> blocks) {
  final out = StringBuffer();
  for (final block in blocks) {
    switch (block) {
      case MarkupHeading(:final text):
        out.writeln('  <h2>${_esc(text)}</h2>');
      case MarkupDivider():
        out.writeln('  <hr />');
      // A rubric, not a blockquote: an instruction, not words to be said.
      case MarkupNote(:final spans):
        out.writeln('  <p class="rubric">${_renderSpans(spans)}</p>');
      case MarkupText(:final spans):
        out.writeln('  <p>${_renderSpans(spans)}</p>');
      // Styled off the class rather than the document around it: any kind of
      // document can hold a list.
      case MarkupList(:final ordered, :final items):
        final tag = ordered ? 'ol' : 'ul';
        out.writeln('  <$tag class="items">');
        for (final item in items) {
          out.writeln('    <li>${_renderSpans(item.spans)}</li>');
        }
        out.writeln('  </$tag>');
      // Outside a <p>: wrapping a <div> in one closes the paragraph early and
      // leaves a stray tag behind.
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
        // A new tab, rather than replacing the prayer someone is in.
        out.write(
          '<a href="${_esc(url)}" target="_blank" rel="noopener">'
          '${_esc(text)}</a>',
        );
      // Unescaped, which is the whole point of a tag reaching here. Authored
      // in this repository, never anything a reader supplies.
      case MarkupHtml(:final html):
        out.write(html);
      case MarkupPlain(:final text):
        out.write(_esc(text));
    }
  }
  return out.toString();
}

/// Derived rather than mapped — `before_communion` becomes
/// `prayerBeforeCommunion` — so it cannot fall out of step with the enum.
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

    // Beside that language's day view, so `start_url` can be `.`.
    final manifest = File(
      '${outDir.path}/${prefixFor(language)}manifest.webmanifest',
    );
    await manifest.parent.create(recursive: true);
    await manifest.writeAsString(
      webManifest(strings: strings[language]!, language: language),
    );
  }

  for (final name in ['icon.svg', ...iconFiles]) {
    await File('site/$name').copy('${outDir.path}/$name');
  }

  await _copyTree(Directory('site/img'), Directory('${outDir.path}/img'));
}

/// Copies [from] into [to], directories and all, so an image added to the
/// advert needs editing only the document that shows it.
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

// ----------------------------------------------------------- service worker

/// Fills site/sw.js with what this build wrote, at the site root — a worker's
/// scope is the directory it is served from, and this one has to reach every
/// page.
Future<void> _writeServiceWorker(Directory outDir) async {
  final (assets, digest) = await _precache(outDir);

  final worker = _fill(await File('site/sw.js').readAsString(), {
    'cache': '$_cachePrefix$digest',
    'assets': jsonEncode(assets),
    'calendars': jsonEncode([
      for (final language in supportedLanguages)
        Calendar.fileName(language, style: CalendarStyle.gregorian),
    ]),
  });

  await File('${outDir.path}/sw.js').writeAsString(worker);
}

/// Everything to precache, relative to the site root, and a digest of the lot.
///
/// The digest names the cache: a constant name leaves `sw.js` byte-identical
/// and a byte-identical worker is never reinstalled, while a build stamp would
/// refetch the whole site on every nightly Pages run. FNV-1a rather than a real
/// hash, since the only question is whether anything changed.
Future<(List<String>, String)> _precache(Directory outDir) async {
  final root = outDir.absolute.path;
  final calendars = {
    for (final language in supportedLanguages)
      Calendar.fileName(language, style: CalendarStyle.gregorian),
  };

  final entries = <(String, File)>[];
  await for (final entity in outDir.list(recursive: true)) {
    if (entity is! File) continue;

    final path = entity.absolute.path.substring(root.length + 1);
    final name = path.split('/').last;

    // The screenshots are twice the weight of the rest of the site together,
    // and the calendar is the other CI job's output, fetched fresh anyway.
    if (path == 'sw.js') continue;
    if (path.startsWith('img/')) continue;
    if (calendars.contains(path)) continue;
    if (_manifestOnlyIcons.contains(path)) continue;

    // A navigation asks for the directory, so cached under `index.html` a page
    // would never be matched.
    final url = name == 'index.html'
        ? path.substring(0, path.length - name.length)
        : path;
    entries.add((url, entity));
  }

  // Sorted so the digest does not depend on the order the filesystem listed in.
  entries.sort((a, b) => a.$1.compareTo(b.$1));

  var digest = 0x811c9dc5;
  void mix(List<int> bytes) {
    for (final byte in bytes) {
      digest = ((digest ^ byte) * 0x01000193) & 0xffffffff;
    }
  }

  final contents = await Future.wait([
    for (final (_, file) in entries) file.readAsBytes(),
  ]);

  for (var i = 0; i < entries.length; i++) {
    // The path too, so a file moved or removed is a change with nothing edited.
    mix(utf8.encode(entries[i].$1));
    mix(contents[i]);
  }

  return (
    [for (final (url, _) in entries) './$url'],
    digest.toRadixString(16).padLeft(8, '0'),
  );
}

/// An unknown placeholder fails the build: left to a per-key replaceAll, one
/// added to the shell and forgotten ships a literal `{{whatever}}`.
String _fill(String template, Map<String, String> values) =>
    template.replaceAllMapped(_placeholder, (match) {
      final value = values[match[1]!];
      if (value == null) throw StateError('site: no value for {{${match[1]}}}');
      return value;
    });

/// Downloads the published calendars, for a local preview.
///
/// The *published* files rather than a local `tool/build_calendar.dart` run,
/// which downloads ~32 MB of iCal to look at a stylesheet change.
Future<void> _fetchPublishedCalendars(Directory outDir) async {
  final client = HttpClient();
  try {
    for (final language in supportedLanguages) {
      final name = Calendar.fileName(language, style: CalendarStyle.gregorian);
      final file = File('${outDir.path}/$name');
      if (file.existsSync()) continue;

      final request = await client.getUrl(defaultCalendarBaseUrl.resolve(name));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        stdout.writeln('site: could not fetch $name (${response.statusCode})');
        continue;
      }
      await response.pipe(file.openWrite());
      stdout.writeln('site: fetched $name');
    }
  } on Object catch (error) {
    // A preview without a calendar still renders, in the empty state.
    stdout.writeln('site: could not fetch calendars ($error)');
  } finally {
    client.close();
  }
}

// ------------------------------------------------------------------- watch

/// Bumped by every successful rebuild; the preview page polls it and reloads.
var _buildSerial = 0;

/// `lib/` is here because site/day.dart compiles the liturgics in, so a fix to
/// the Paschalion has to reach the preview too.
final _watched = [
  'site',
  'res/prayers',
  'lib',
  'pubspec.yaml',
  ...supportedLanguages.map(privacySource),
];

/// Rebuilds whenever a source file changes.
void _watch(Directory outDir, String baseUrl) {
  Timer? debounce;
  var building = false;
  var again = false;

  Future<void> rebuild() async {
    // A save landing mid-build is served after it rather than dropped, which
    // would leave the preview stale until the next save.
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
        // A syntax error while editing is ordinary: keep watching, and leave
        // the last build that worked served.
        stderr.writeln('site: rebuild failed ($error)');
      }
    } while (again);
    building = false;
  }

  void schedule(String path) {
    // Editors write a file several times to save it once, and the compile is
    // the better part of a second, so a rebuild per event queues up.
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 150), rebuild);
  }

  for (final path in _watched) {
    final entity = FileSystemEntity.isDirectorySync(path)
        ? Directory(path)
        : File(path);
    if (!entity.existsSync()) continue;

    entity.watch(recursive: entity is Directory).listen((event) {
      // The generated localizations are written by the Flutter build and would
      // otherwise rebuild the site for no reason.
      if (event.path.contains('app_localizations')) return;
      schedule(event.path);
    });
  }

  stdout.writeln('site: watching ${_watched.join(', ')}');
}

/// Injected on the way out by the preview server, never written into the built
/// output: the deployed site must not poll anything.
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

/// Registers the worker, from every page so arriving at a prayer caches the
/// whole site.
///
/// `data-root` rather than a per-page path so the string is identical on every
/// page, which is what lets the preview swap it for [_unregisterScript].
const _registerScript = '''
<script>
      if ('serviceWorker' in navigator) {
        addEventListener('load', function () {
          navigator.serviceWorker
            .register(document.body.dataset.root + 'sw.js')
            .catch(function () {});
        });
      }
    </script>''';

/// All that joins the authored badge to [_installScript]. Public so test/tool/
/// can hold both documents to carrying it.
const installSectionClass = 'webapp';

/// Only Chromium has an install API, so the badge prompts where the event was
/// handed over and reveals that browser's own route where it was not. Those
/// lines are authored in `site/download_*.md`, being prose to translate.
///
/// The section ships hidden and is revealed here, so it never appears without
/// JavaScript to work.
const _installScript =
    '''
<script>
      (function () {
        var section = document.querySelector('.$installSectionClass');
        var button = section && section.querySelector('button');
        if (!button) return;

        // Inside the installed app is the one place the badge stays hidden.
        var app = matchMedia('(display-mode: standalone)');
        if (app.matches || navigator.standalone) return;

        // Installing does not reload: Chrome hands this document to the app
        // window. Per document, unlike `appinstalled`, which also fires on a
        // tab that stays a tab — as it always does on Android.
        app.addEventListener('change', function (event) {
          section.hidden = event.matches;
        });

        var agent = navigator.userAgent;
        // iPadOS calls itself a Mac; the touch points tell the two apart.
        var ios = /iPad|iPhone|iPod/.test(agent) ||
          (/Macintosh/.test(agent) && navigator.maxTouchPoints > 1);
        var safari = !ios && /Macintosh/.test(agent) &&
          /Safari/.test(agent) && !/Chrome|Chromium/.test(agent);
        var how = section.querySelector(
          '[data-how="' + (ios ? 'ios' : safari ? 'mac' : 'other') + '"]');

        var offer = null;
        addEventListener('beforeinstallprompt', function (event) {
          // Or the browser shows its own bar as well as this badge.
          event.preventDefault();
          offer = event;
        });

        button.addEventListener('click', function () {
          if (offer) {
            offer.prompt();
            offer = null;
          } else if (how) {
            how.hidden = false;
          }
        });

        section.hidden = false;
      })();
    </script>''';

/// What the preview serves in its place, since a worker answering from its
/// cache serves the page from before the edit. It unregisters rather than
/// merely skipping: one installed by an earlier session outlives it. Only this
/// site's caches go, since anything else on localhost belongs to something else.
const _unregisterScript =
    '''
<script>
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.getRegistrations().then(function (registrations) {
          registrations.forEach(function (registration) { registration.unregister(); });
        });
        caches.keys().then(function (names) {
          names.forEach(function (name) {
            if (name.indexOf('$_cachePrefix') === 0) caches.delete(name);
          });
        });
      }
    </script>''';

// -------------------------------------------------------------------- serve

const _contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  // Served as anything else the manifest is ignored, with no error to say why.
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.png': 'image/png',
  // Without this the favicon is a byte stream and the browser declines it,
  // which reads as broken artwork rather than as a missing line here.
  '.svg': 'image/svg+xml',
};

/// Only ever a preview: GitHub Pages serves the deployed site, so nothing here
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
    // Refuse anything that escapes the output directory.
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

    // Injected here rather than built into the page, so the deployed site
    // never carries it. The worker goes the other way for the same reason.
    if (extension == '.html') {
      final html = await file.readAsString();
      request.response.write(
        html
            .replaceFirst(_registerScript, _unregisterScript)
            .replaceFirst('</body>', '$_reloadScript</body>'),
      );
      await request.response.close();
      continue;
    }

    await file.openRead().pipe(request.response);
  }
}
