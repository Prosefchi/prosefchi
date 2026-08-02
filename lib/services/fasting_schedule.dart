import '../l10n/app_localizations.dart';
import '../l10n/liturgical_labels.dart';
import '../liturgics/fasting.dart';
import '../liturgics/paschalion.dart';
import '../models/calendar.dart';
import '../models/reminder.dart';
import 'calendar_repository.dart';
import 'notification_service.dart';

/// A day that fasts, and the rule published for it where there is one.
typedef FastingDay = ({DateTime date, FastAllowance? allowance});

/// The fast days to schedule reminders for, starting at [from].
///
/// This cannot repeat daily the way a prayer reminder does, since it must not
/// fire on the days between and a scheduled notification cannot be withdrawn.
/// So every day is scheduled separately and refilled whenever the app opens.
///
/// [calendar] wins wherever it reaches, computed seasons past its end. Its
/// emoji markers are no use here: they record an allowance, and all 843 strict
/// fast days in the feed carry none.
List<FastingDay> fastingDaysFrom(
  DateTime from, {
  Calendar? calendar,
  int within = 60,
  int limit = FastingReminder.idCapacity,
  required CalendarStyle style,
}) {
  final days = <FastingDay>[];

  for (var offset = 0; offset < within && days.length < limit; offset++) {
    final date = addDays(from, offset);
    final published = calendar?.forDate(date);

    if (published != null) {
      if (published.fasts) {
        days.add((date: date, allowance: published.fastAllowance));
      }
    } else if (isFastDay(date, style: style)) {
      days.add((date: date, allowance: null));
    }
  }

  return days;
}

/// The single path that applies [fastingDaysFrom], replacing the whole block
/// whether or not anything changed. A finite horizon, so without a refill it
/// simply runs out.
Future<void> refreshFastingReminders({
  required FastingReminder reminder,
  required CalendarRepository calendars,
  required ReminderScheduler scheduler,
  required String language,
  required AppLocalizations l10n,
  DateTime? from,
  required CalendarStyle style,
}) async {
  final calendar = await calendars.load(language, style: style);
  final days = fastingDaysFrom(
    from ?? DateTime.now(),
    calendar: calendar,
    style: style,
  );

  await scheduler.applyFasting(
    reminder,
    days: [
      for (final day in days)
        // The published rule where there is one, so the notification says
        // "Strict Fast" rather than merely that the day fasts.
        (
          date: day.date,
          body:
              l10n.fastAllowanceLabel(day.allowance) ??
              l10n.fastingReminderBody,
        ),
    ],
    channelName: l10n.fastingReminder,
    title: l10n.fastingReminder,
  );
}
