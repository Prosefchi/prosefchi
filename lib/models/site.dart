// Where the website is, and how it lays languages out in its URLs.
//
// Flutter-free, like everything else the site compiles, and shared by three
// things that would otherwise each state it: tool/build_site.dart writes the
// pages at these paths, site/day.dart resolves `?lang=` against the same rule,
// and the app links to the privacy policy published there. Two statements of it
// would mean the generator writing one set of URLs and something else sending
// readers to another — a 404 on the one path nobody tests by hand.

import 'calendar.dart' show supportedLanguages;

/// Where the website is served.
///
/// Deliberately **not** where the calendar is fetched from — that is
/// [defaultCalendarBaseUrl] below. This is only ever used to build a link a
/// reader follows, so it is the address the site is actually served at and the
/// one worth showing them.
final siteUrl = Uri.parse('https://prosefchi.org/');

/// Where the published calendar JSON is fetched from.
///
/// GitHub Pages by deliberate choice, and **not** [siteUrl]. A shipped build
/// cannot be repointed, so the installs already out there ask for this host; if
/// it ever has to move the plan is to publish from both, ship an update that
/// switches over, and retire this one only once the old installs have drained.
/// Do not "fix" either of the two into the other.
///
/// Here rather than beside the repository that fetches it because
/// tool/build_site.dart needs it too — `--calendar` pulls the published files
/// for a preview — and that runs under `dart run`, which cannot reach anything
/// importing Flutter. services/calendar_repository.dart re-exports it.
final defaultCalendarBaseUrl = Uri.parse(
  'https://prosefchi.github.io/prosefchi/',
);

/// The path prefix a language's pages sit under, relative to the site root.
///
/// English is served at the root and every other language under its own code,
/// so the canonical URL of the front page carries nothing extra.
String prefixFor(String language) =>
    language == supportedLanguages.first ? '' : '$language/';

/// The privacy policy, relative to a language's prefix.
///
/// Google Play's listing points at the English one, so moving this path means
/// editing that entry too — a store listing is not rebuilt by anything here.
const privacyPath = 'about/privacy/';

/// The privacy policy page for [language], relative to the site root.
///
/// The composition, not just the parts, because three things reach that page
/// and each concatenating the two constants for itself would prove only that
/// the constants concatenate: tool/build_site.dart writes the page here, the
/// site's own about row links to it, and the app's about section resolves it
/// against [siteUrl]. Moving the policy is then one edit rather than three, and
/// the one that would have been missed is a store listing pointing at a 404.
String privacyPagePath(String language) => '${prefixFor(language)}$privacyPath';
