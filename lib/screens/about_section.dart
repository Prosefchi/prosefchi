import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/site.dart';
import '../services/calendar_repository.dart' show languageFor;
import 'link.dart';

/// Where the repository lives.
final repositoryUrl = Uri.parse('https://github.com/Prosefchi/prosefchi');

/// The privacy policy for [language], on the website.
///
/// [privacyPagePath] rather than a URL written out here, because that is what
/// tool/build_site.dart writes the page at: a policy Google Play requires a
/// working link to is not somewhere a second spelling can be allowed to drift.
///
/// The language is the content language rather than the device's, so a reader
/// who chose Greek is sent to the Greek policy — the same document, and the
/// only one of the two they can read.
Uri privacyPolicyUrl(String language) =>
    siteUrl.resolve(privacyPagePath(language));

/// The version, the source, and the licences of everything the app depends on.
///
/// The version is read from the bundle rather than written here, where it would
/// drift from `pubspec.yaml` the first time someone bumped one and not the
/// other.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key, this.packageInfo, this.launch});

  /// Injectable: `package_info_plus` and `url_launcher` both go through
  /// platform channels, which are unavailable under `flutter test`.
  final Future<PackageInfo> Function()? packageInfo;
  final Future<bool> Function(Uri url, {LaunchMode mode})? launch;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await (widget.packageInfo ?? PackageInfo.fromPlatform)();
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    } on Object {
      // Not worth failing the screen over; the row simply stays quiet.
    }
  }

  /// Deliberately not the in-app browser the prayer texts use: the repository
  /// is somewhere to go and act — sign in, clone, open an issue — rather than
  /// something to read and come back from.
  Future<void> _openRepository() => openLink(
    context,
    repositoryUrl,
    mode: LaunchMode.externalApplication,
    launch: widget.launch,
  );

  /// The default in-app browser view, unlike the repository above it: a policy
  /// is read and returned from, so closing it should put the reader back in
  /// settings rather than leave the app behind a browser.
  Future<void> _openPrivacyPolicy() => openLink(
    context,
    privacyPolicyUrl(languageFor(Localizations.localeOf(context))),
    launch: widget.launch,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.code),
          title: Text(l10n.sourceCode),
          subtitle: Text(l10n.sourceCodeSubtitle),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: _openRepository,
        ),
        // Above the version rather than at the end, since it is the row a
        // reader comes to this section looking for and the two below it are
        // reference.
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.privacyPolicy),
          subtitle: Text(l10n.privacyPolicySubtitle),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: _openPrivacyPolicy,
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.appVersion),
          subtitle: Text(_version ?? '—'),
        ),
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(l10n.openSourceLicences),
          trailing: const Icon(Icons.chevron_right),
          // Flutter's own page, which enumerates every dependency's licence
          // from the build rather than from a list we would have to maintain.
          onTap: () => showLicensePage(
            context: context,
            applicationName: l10n.appTitle,
            applicationVersion: _version,
          ),
        ),
      ],
    );
  }
}
