import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the calendar is kept between launches.
///
/// An interface because `testWidgets` runs inside a `FakeAsync` zone where a
/// real filesystem future never completes: a write hangs until the timeout.
abstract interface class CalendarStore {
  Future<String?> read(String name);

  /// Without reading it: the calendar runs to about a megabyte, and `refresh`
  /// only needs to know it is there.
  Future<bool> exists(String name);
  Future<void> write(String name, String contents);
  Future<void> delete(String name);
}

/// Application Support rather than the cache directory: the OS purges caches
/// under storage pressure, and losing this offline loses the saint of the day.
class FileCalendarStore implements CalendarStore {
  FileCalendarStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  /// path_provider does not cache, so each call is a platform-channel round
  /// trip. A launch does five or six of these where one will do.
  Future<Directory>? _resolved;

  @override
  Future<String?> read(String name) async {
    final file = await _fileFor(name);
    return file.existsSync() ? file.readAsString() : null;
  }

  @override
  Future<bool> exists(String name) async => (await _fileFor(name)).existsSync();

  @override
  Future<void> write(String name, String contents) async {
    final file = await _fileFor(name);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  @override
  Future<void> delete(String name) async {
    final file = await _fileFor(name);
    if (file.existsSync()) await file.delete();
  }

  Future<File> _fileFor(String name) async {
    final directory = await (_resolved ??= _directory());
    return File('${directory.path}/calendar/$name');
  }
}
