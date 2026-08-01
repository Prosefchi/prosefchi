// The website's address, and where it puts a language's pages and the privacy
// policy. Shared by the generator, the site's own scripts and the app, so none
// of them can link to a page another one does not write.

import 'calendar.dart' show supportedLanguages;

/// Where the website is served.
final siteUrl = Uri.parse('https://prosefchi.org/');

/// Where the published calendar JSON is fetched from.
///
/// Not [siteUrl]: a shipped build cannot be repointed, so the installs already
/// out there ask for this host. Do not fold the two into one.
final defaultCalendarBaseUrl = Uri.parse(
  'https://prosefchi.github.io/prosefchi/',
);

/// The path prefix a language's pages sit under. English is served at the root.
String prefixFor(String language) =>
    language == supportedLanguages.first ? '' : '$language/';

/// The privacy policy page for [language], relative to the site root.
String privacyPagePath(String language) =>
    '${prefixFor(language)}about/privacy/';

/// The privacy policy for [language].
///
/// Google Play's listing points at the English one, so moving it means editing
/// that entry too.
Uri privacyPolicyUrl(String language) =>
    siteUrl.resolve(privacyPagePath(language));
