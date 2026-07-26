import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serves only the assets it is given, and throws for anything else the way the
/// real bundle does for an asset that was never bundled.
class FakeBundle extends CachingAssetBundle {
  FakeBundle(this.contents);

  final Map<String, String> contents;

  /// Every key asked for, in order, so a test can assert what was read and how
  /// often.
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    final value = contents[key];
    if (value == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(utf8.encode(value));
  }
}
