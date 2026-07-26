import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prosefchi/services/calendar_repository.dart';
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

/// A repository holding no calendar and unable to fetch one, so the computed
/// liturgical layer decides.
///
/// What most screen tests want. Both defaults it replaces are traps under
/// `flutter test`: a real `FileCalendarStore` reaches path_provider, and a real
/// `http.Client` reaches the network — and inside `FakeAsync` the resulting
/// futures never complete, so the test hangs rather than failing.
CalendarRepository offlineCalendars() => CalendarRepository(
  baseUrl: Uri.parse('https://example.invalid/'),
  store: MemoryCalendarStore(),
  client: MockClient((_) async => http.Response('', 404)),
);
