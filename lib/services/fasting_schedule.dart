import '../l10n/app_localizations.dart';
import '../liturgics/fasting.dart';
import '../liturgics/paschalion.dart';
import '../models/calendar.dart';
import '../models/reminder.dart';
import 'calendar_repository.dart';
import 'notification_service.dart';

/// A day that fasts, and the rule stated for it where one is published.
typedef FastingDay = ({DateTime date, String? rule});

/// The fast days to schedule reminders for, starting at [from].
///
/// A fasting reminder cannot repeat daily the way a prayer reminder does,
/// because it must not fire on the days between. Local notifications fix their
/// content when scheduled and give no hook to withdraw one before it appears,
/// so every day is scheduled separately and this list is refilled whenever the
/// app opens.
///
/// [calendar] is used wherever it reaches, since it carries the Archdiocese's
/// own ruling and the wording to put in the notification. Past its end the
/// computed seasons take over, which is the same precedence the rest of the app
/// follows. The calendar's own emoji markers are no use here: they record an
/// allowance, and all 843 strict fast days in the feed carry none.
///
/// [limit] is the size of the id block the scheduler cancels and refills, so it
/// defaults to that one constant rather than repeating the number — see
/// [FastingReminder.idCapacity] for why it is 30. Through Great Lent every day
/// fasts, so a [within] of 60 would otherwise ask for 51 at once.
List<FastingDay> fastingDaysFrom(
  DateTime from, {
  Calendar? calendar,
  int within = 60,
  int limit = FastingReminder.idCapacity,
}) {
  final days = <FastingDay>[];

  for (var offset = 0; offset < within && days.length < limit; offset++) {
    final date = addDays(from, offset);
    final published = calendar?.forDate(date);

    if (published != null) {
      if (published.fasts) days.add((date: date, rule: published.fasting));
    } else if (isFastDay(date)) {
      days.add((date: date, rule: null));
    }
  }

  return days;
}

/// Rebuilds the fasting reminder schedule.
///
/// The single path that applies [fastingDaysFrom]: used by the reminders screen
/// when the switch is touched, and by `refreshReminders` for every other
/// occasion. The schedule is a finite horizon rather than a repeating alarm, so
/// without a refill it simply runs out. It replaces the whole block whether or
/// not anything has changed.
Future<void> refreshFastingReminders({
  required FastingReminder reminder,
  required CalendarRepository calendars,
  required ReminderScheduler scheduler,
  required String language,
  required AppLocalizations l10n,
  DateTime? from,
}) async {
  final calendar = await calendars.load(language);
  final days = fastingDaysFrom(from ?? DateTime.now(), calendar: calendar);

  await scheduler.applyFasting(
    reminder,
    days: [
      for (final day in days)
        // The published rule where there is one, so the notification says
        // "Strict Fast" rather than merely that the day fasts.
        (date: day.date, body: day.rule ?? l10n.fastingReminderBody),
    ],
    channelName: l10n.fastingReminder,
    title: l10n.fastingReminder,
  );
}
