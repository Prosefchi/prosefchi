import 'package:flutter_test/flutter_test.dart';
import 'package:prosefchi/models/prayer.dart';
import 'package:prosefchi/models/reminder.dart';
import 'package:prosefchi/services/reminder_refresh.dart';
import 'package:prosefchi/services/settings_controller.dart';

import '../support/memory_calendar_store.dart';
import '../support/reminder_doubles.dart';

ReminderRefresher refresherFor(
  MemoryReminderStore store,
  RecordingScheduler scheduler,
) => ReminderRefresher(
  // No store and no load(): nothing here reads a stored language, and
  // effectiveLanguage resolves the device's without touching one.
  settings: SettingsController(),
  store: store,
  scheduler: scheduler,
  calendars: offlineCalendars(),
);

MemoryReminderStore storeWithMorningOn() => MemoryReminderStore({
  PrayerOccasion.morning: Reminder.defaultFor(
    PrayerOccasion.morning,
  ).copyWith(enabled: true),
});

/// Throws the first time, then behaves.
class _FailsOnceScheduler extends RecordingScheduler {
  bool _thrown = false;

  @override
  Future<void> apply(
    Reminder reminder, {
    required String channelName,
    required String title,
    required String body,
  }) async {
    if (!_thrown) {
      _thrown = true;
      throw StateError('no notification channel');
    }
    return super.apply(
      reminder,
      channelName: channelName,
      title: title,
      body: body,
    );
  }
}

void main() {
  // Only for the AppLifecycleListener in start(), which reaches
  // WidgetsBinding.instance. The rest of these need no binding at all.
  TestWidgetsFlutterBinding.ensureInitialized();

  // A prayer reminder is not a standing daily alarm — see refreshReminders for
  // the mechanism. Nothing but the app re-arming it recovers from a broken
  // chain, which is what these first tests pin.
  test('re-arms the enabled prayer reminders', () async {
    final scheduler = RecordingScheduler();
    await refresherFor(storeWithMorningOn(), scheduler).refresh();

    expect(scheduler.applied.map((reminder) => reminder.occasion), [
      PrayerOccasion.morning,
    ]);
  });

  test('leaves the disabled ones alone', () async {
    final scheduler = RecordingScheduler();
    await refresherFor(MemoryReminderStore(), scheduler).refresh();

    // Every reminder ships off, so this is the ordinary launch: it must not
    // reach the notification plugin at all.
    expect(scheduler.applied, isEmpty);
    expect(scheduler.fastingApplies, 0);
  });

  test('refills the fasting block', () async {
    final store = MemoryReminderStore()
      ..fasting = const FastingReminder.initial().copyWith(enabled: true);
    final scheduler = RecordingScheduler();

    await refresherFor(store, scheduler).refresh();

    // Every Wednesday and Friday fasts, so a 60 day lookahead always finds some.
    expect(scheduler.fastingDays, isNotEmpty);
  });

  test('does not rebuild the schedule twice in a day', () async {
    final scheduler = RecordingScheduler();
    final refresher = refresherFor(storeWithMorningOn(), scheduler);

    await refresher.refresh();
    await refresher.refresh();

    expect(scheduler.applied, hasLength(1));
  });

  test('retries after a failure rather than writing the day off', () async {
    final scheduler = _FailsOnceScheduler();
    final refresher = refresherFor(storeWithMorningOn(), scheduler);

    await refresher.refresh();
    expect(scheduler.applied, isEmpty, reason: 'the first attempt threw');

    // The day is stamped only on success, so the next resume tries again. A
    // stamp before the work would have silenced this until the next cold start.
    await refresher.refresh();
    expect(scheduler.applied, hasLength(1));
  });

  test('start also re-arms, and stops on dispose', () async {
    final scheduler = RecordingScheduler();
    final refresher = refresherFor(storeWithMorningOn(), scheduler)..start();

    // start() kicks off a refresh it does not await, so let it land.
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.applied, hasLength(1));

    refresher.dispose();
  });
}
