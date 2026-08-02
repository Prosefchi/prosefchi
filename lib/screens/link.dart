import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Opens [url], and says so when nothing can. The one place that decides where
/// a link opens and what a failure looks like.
///
/// The default keeps the reader in the app: [LaunchMode.inAppBrowserView] is
/// Custom Tabs and `SFSafariViewController`, a real browser drawn over the app,
/// so closing it returns to the prayer. The browser rather than a bare
/// `inAppWebView` because it shows the address.
Future<void> openLink(
  BuildContext context,
  Uri url, {
  LaunchMode mode = LaunchMode.inAppBrowserView,
  Future<bool> Function(Uri url, {LaunchMode mode})? launch,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final open = launch ?? launchUrl;

  // The mode is a preference, not a guarantee, and opening the link somewhere
  // beats reporting a failure the reader can do nothing about.
  if (await open(url, mode: mode)) return;
  if (mode != LaunchMode.platformDefault &&
      await open(url, mode: LaunchMode.platformDefault)) {
    return;
  }

  messenger.showSnackBar(SnackBar(content: Text(l10n.couldNotOpenLink)));
}
