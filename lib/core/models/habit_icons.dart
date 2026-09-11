import 'package:flutter/material.dart';

/// The icons a habit can be given.
///
/// A fixed table of *const* [IconData] rather than a stored code point.
/// Flutter's `--tree-shake-icons` pass can only keep glyphs it can see
/// statically; an `IconData(someInt)` built at runtime makes the release build
/// fail with "Avoid non-constant invocations of IconData". Storing a key into
/// this table keeps every glyph reachable and the stored value readable in a
/// backup file.
class HabitIcons {
  const HabitIcons._();

  static const String fallbackKey = 'check';

  static const Map<String, IconData> catalog = <String, IconData>{
    'check': Icons.check_circle_outline_rounded,
    'run': Icons.directions_run_rounded,
    'gym': Icons.fitness_center_rounded,
    'walk': Icons.directions_walk_rounded,
    'bike': Icons.directions_bike_rounded,
    'water': Icons.water_drop_outlined,
    'food': Icons.restaurant_rounded,
    'sleep': Icons.bedtime_outlined,
    'meditate': Icons.self_improvement_rounded,
    'read': Icons.menu_book_rounded,
    'write': Icons.edit_note_rounded,
    'study': Icons.school_rounded,
    'code': Icons.code_rounded,
    'work': Icons.work_outline_rounded,
    'focus': Icons.center_focus_strong_rounded,
    'money': Icons.savings_outlined,
    'clean': Icons.cleaning_services_rounded,
    'call': Icons.phone_in_talk_rounded,
    'music': Icons.music_note_rounded,
    'art': Icons.brush_rounded,
    'nature': Icons.park_rounded,
    'sun': Icons.wb_sunny_rounded,
    'heart': Icons.favorite_border_rounded,
    'star': Icons.star_border_rounded,
  };

  static IconData resolve(String? key) =>
      catalog[key] ?? catalog[fallbackKey]!;

  static List<String> get keys => catalog.keys.toList();
}
