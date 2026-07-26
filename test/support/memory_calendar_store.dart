import 'package:prosefchi/services/calendar_store.dart';

/// An in-memory [CalendarStore] for tests.
///
/// Widget tests run inside a `FakeAsync` zone where real filesystem futures
/// never complete, so anything touching `dart:io` hangs until the test times
/// out. These futures resolve on the microtask queue, which `FakeAsync` does
/// drive.
class MemoryCalendarStore implements CalendarStore {
  final Map<String, String> entries = {};

  @override
  Future<String?> read(String name) async => entries[name];

  @override
  Future<bool> exists(String name) async => entries.containsKey(name);

  @override
  Future<void> write(String name, String contents) async =>
      entries[name] = contents;

  @override
  Future<void> delete(String name) async => entries.remove(name);
}
