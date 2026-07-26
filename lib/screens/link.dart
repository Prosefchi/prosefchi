import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Opens [url], and says so when nothing can.
///
/// One copy of the policy — where a link opens, and what a failure looks like.
/// A device with no browser is rare enough that two copies would drift for a
/// long time before anyone noticed.
///
/// The default keeps the reader in the app. [LaunchMode.inAppBrowserView] is
/// Android's Custom Tabs and iOS's `SFSafariViewController`: a real browser
/// drawn over the app rather than a separate one switched to, so closing it
/// returns to the prayer instead of leaving the app in the background. It is
/// the browser rather than a bare `inAppWebView` on purpose — it shows the
/// address, so a reader can see whose text they are being sent to, and it is
/// updated by the platform rather than by this app.
Future<void> openLink(
  BuildContext context,
  Uri url, {
  LaunchMode mode = LaunchMode.inAppBrowserView,
  Future<bool> Function(Uri url, {LaunchMode mode})? launch,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final open = launch ?? launchUrl;

  // The mode is a preference, not a guarantee: a device with no Custom Tabs
  // provider cannot honour it. Opening the link somewhere beats reporting a
  // failure the reader can do nothing about.
  if (await open(url, mode: mode)) return;
  if (mode != LaunchMode.platformDefault &&
      await open(url, mode: LaunchMode.platformDefault)) {
    return;
  }

  messenger.showSnackBar(SnackBar(content: Text(l10n.couldNotOpenLink)));
}
