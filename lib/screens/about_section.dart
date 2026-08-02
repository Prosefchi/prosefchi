import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/site.dart' show privacyPolicyUrl;
import '../services/calendar_repository.dart' show languageFor;
import 'link.dart';

/// Where the repository lives.
final repositoryUrl = Uri.parse('https://github.com/Prosefchi/prosefchi');

/// The version, the source, and the licences of everything the app depends on.
/// The version is read from the bundle, so it cannot drift from `pubspec.yaml`.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key, this.packageInfo, this.launch});

  /// Injectable: `package_info_plus` and `url_launcher` both reach platform
  /// channels, which are unavailable under `flutter test`.
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

  /// Not the in-app browser the prayer texts use: the repository is somewhere
  /// to go and act, not to read and come back from.
  Future<void> _openRepository() => openLink(
    context,
    repositoryUrl,
    mode: LaunchMode.externalApplication,
    launch: widget.launch,
  );

  /// The in-app browser, unlike the repository above: a policy is read and
  /// returned from.
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
          // Flutter's own page, enumerated from the build rather than a list
          // we would have to maintain.
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
