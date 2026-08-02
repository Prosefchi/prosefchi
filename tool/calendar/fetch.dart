// Fetching, with the on-disk cache the --cache flag reuses.
//
// Shared by every source because the reason for it is the same each time: a
// full build downloads tens of megabytes, and looking at a parsing change
// should not cost that twice.

import 'dart:convert';
import 'dart:io';

/// Where a cached response for [key] lives. Gitignored, like all of .dart_tool.
File _cacheFile(String key) => File('.dart_tool/calendar_cache/$key');

/// Fetches [url], writing the body to the cache under [key].
///
/// With [useCache] a previously written copy is returned untouched and nothing
/// is requested. [label] only prefixes the progress lines.
Future<String> fetch(
  String url, {
  required String key,
  required String label,
  required bool useCache,
}) async {
  final cache = _cacheFile(key);
  if (useCache && cache.existsSync()) {
    stdout.writeln('$label: using cached ${cache.path}');
    return cache.readAsString();
  }

  stdout.writeln('$label: fetching $url');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    final body = await response.transform(utf8.decoder).join();
    await cache.parent.create(recursive: true);
    await cache.writeAsString(body);
    return body;
  } finally {
    client.close();
  }
}
