import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  static String formatDate(DateTime date) =>
      DateFormat('MMM d, yyyy').format(date);

  static String formatDateWithDay(DateTime date) =>
      DateFormat('EEEE, MMMM d').format(date);

  static String formatShortDate(DateTime date) =>
      DateFormat('MMM d').format(date);

  static String formatTime(DateTime date) => DateFormat('h:mm a').format(date);

  static String formatDayName(DateTime date) => DateFormat('EEE').format(date);

  static String formatMonthYear(DateTime date) =>
      DateFormat('MMMM yyyy').format(date);

  static int daysUntil(DateTime target) {
    // Anchor in UTC so the difference is an exact multiple of 24h; local
    // midnights across a DST change are 23/25h apart and inDays truncates.
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final targetDay = DateTime.utc(target.year, target.month, target.day);
    return targetDay.difference(today).inDays;
  }

  static String daysUntilLabel(DateTime target) {
    final days = daysUntil(target);
    if (days < 0) return '${days.abs()}d overdue';
    if (days == 0) return 'Due today';
    if (days == 1) return '1 day left';
    return '$days days left';
  }

  /// Exact calendar-day difference (a - b), immune to DST: local midnights
  /// can be 23/25h apart, which a plain `difference().inDays` truncates.
  static int dayDifference(DateTime a, DateTime b) => DateTime.utc(
        a.year,
        a.month,
        a.day,
      ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime date) => isSameDay(date, DateTime.now());

  static DateTime normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static int weekdayIndex(DateTime date) =>
      date.weekday % 7; // 0=Sunday, 1=Monday, ..., 6=Saturday

  static List<DateTime> daysInMonth(int year, int month) {
    final last = DateTime(year, month + 1, 0);
    return List.generate(
      last.day,
      (i) => DateTime(year, month, i + 1),
    );
  }

  static String greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
