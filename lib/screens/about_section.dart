import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import 'link.dart';

/// Where the repository lives.
final repositoryUrl = Uri.parse('https://github.com/Prosefchi/prosefchi');

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
  final Future<bool> Function(Uri url)? launch;

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

  Future<void> _openRepository() =>
      openLink(context, repositoryUrl, launch: widget.launch);

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
