import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar.dart' show CalendarStyle;

/// The old and new calendar, offered in settings and in the welcome flow.
///
/// The subtitle is load-bearing: without it the obvious guess is that this
/// moves Pascha too.
class CalendarStyleOptions extends StatelessWidget {
  const CalendarStyleOptions({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CalendarStyle value;
  final ValueChanged<CalendarStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return RadioGroup<CalendarStyle>(
      groupValue: value,
      onChanged: (style) {
        if (style != null) onChanged(style);
      },
      child: Column(
        children: [
          for (final style in CalendarStyle.values) _tile(l10n, style),
        ],
      ),
    );
  }

  static Widget _tile(AppLocalizations l10n, CalendarStyle style) {
    final (name, note) = switch (style) {
      CalendarStyle.gregorian => (
        l10n.calendarStyleNew,
        l10n.calendarStyleNewNote,
      ),
      CalendarStyle.julian => (
        l10n.calendarStyleOld,
        l10n.calendarStyleOldNote,
      ),
    };
    return RadioListTile<CalendarStyle>(
      value: style,
      title: Text(name),
      subtitle: Text(note),
    );
  }
}
