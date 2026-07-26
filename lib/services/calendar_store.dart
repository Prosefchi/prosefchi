import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the calendar is kept between launches.
///
/// An abstraction rather than direct `File` use so widget tests can supply an
/// in-memory implementation. `testWidgets` runs its body inside a `FakeAsync`
/// zone, and real filesystem futures never complete there — a write simply
/// hangs until the test times out.
abstract interface class CalendarStore {
  Future<String?> read(String name);

  /// Whether [name] has been stored, without reading it.
  ///
  /// The calendar runs to about a megabyte; `refresh` only needs to know it is
  /// there before sending a conditional request.
  Future<bool> exists(String name);
  Future<void> write(String name, String contents);
  Future<void> delete(String name);
}

/// The real store: files under the platform's application support directory.
///
/// Application Support rather than the cache directory, because the OS purges
/// caches under storage pressure and losing this while offline means losing
/// the saint of the day with no way to get it back.
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
