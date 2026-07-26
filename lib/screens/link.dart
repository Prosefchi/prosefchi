import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Opens [url] outside the app, and says so when nothing can.
///
/// One copy of the policy — which launch mode, and what a failure looks like.
/// A device with no browser is rare enough that two copies would drift for a
/// long time before anyone noticed.
Future<void> openLink(
  BuildContext context,
  Uri url, {
  Future<bool> Function(Uri url)? launch,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  if (await (launch ?? _launch)(url)) return;

  messenger.showSnackBar(SnackBar(content: Text(l10n.couldNotOpenLink)));
}

/// Injectable at every call site: `url_launcher` goes through a platform
/// channel, which is unavailable under `flutter test`.
Future<bool> _launch(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
