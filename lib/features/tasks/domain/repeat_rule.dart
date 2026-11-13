/// How a task repeats. Stored on [Task.repeat] as the enum's name, so the
/// value is readable in backups and on the sync wire.
enum RepeatRule { daily, weekdays, weekly, monthly, yearly }

extension RepeatRuleInfo on RepeatRule {
  String get label => switch (this) {
        RepeatRule.daily => 'Every day',
        RepeatRule.weekdays => 'Every weekday',
        RepeatRule.weekly => 'Every week',
        RepeatRule.monthly => 'Every month',
        RepeatRule.yearly => 'Every year',
      };

  /// The next due date strictly after [from], keeping its time of day.
  ///
  /// Calendar arithmetic, not `Duration`: adding 24-hour days across a
  /// daylight-saving change would drift the time. Month-end dates clamp, so
  /// a task due on the 31st repeats on the last day of shorter months.
  DateTime next(DateTime from) {
    DateTime at(int y, int m, int d) =>
        DateTime(y, m, d, from.hour, from.minute);
    switch (this) {
      case RepeatRule.daily:
        return at(from.year, from.month, from.day + 1);
      case RepeatRule.weekdays:
        var d = at(from.year, from.month, from.day + 1);
        while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          d = at(d.year, d.month, d.day + 1);
        }
        return d;
      case RepeatRule.weekly:
        return at(from.year, from.month, from.day + 7);
      case RepeatRule.monthly:
        final lastDay = DateTime(from.year, from.month + 2, 0).day;
        return at(
            from.year, from.month + 1, from.day > lastDay ? lastDay : from.day);
      case RepeatRule.yearly:
        final lastDay = DateTime(from.year + 1, from.month + 1, 0).day;
        return at(
            from.year + 1, from.month, from.day > lastDay ? lastDay : from.day);
    }
  }
}

RepeatRule? parseRepeatRule(String? value) {
  if (value == null || value.isEmpty) return null;
  for (final r in RepeatRule.values) {
    if (r.name == value) return r;
  }
  return null;
}
