// Command-line parsing for the two build scripts.
//
// Shared so a fix to one reaches the other. Both take the same shape of
// argument and neither needs anything `package:args` would add.

/// Parses `--name value` and bare `--flag` pairs.
///
/// A bare flag maps to the empty string, so `options.containsKey('cache')`
/// answers "was it given" and `options['out']` answers "with what". Anything
/// not starting with `--` is ignored.
Map<String, String> parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (!args[i].startsWith('--')) continue;
    final name = args[i].substring(2);
    // A following value only belongs to this flag if it is not itself a flag,
    // which is what lets `--serve` stand alone before `--out public`.
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      options[name] = args[++i];
    } else {
      options[name] = '';
    }
  }
  return options;
}
