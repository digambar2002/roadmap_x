// All Isar data models are defined in this single file
// to avoid cross-file circular import issues with isar_generator.
import 'package:isar_community/isar.dart';

part 'models.g.dart';

// ─────────────────────────────────────────────────────────
// Goal
// ─────────────────────────────────────────────────────────

@Collection()
class Goal {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;
  late String name;
  late String description;
  late String emoji;
  late int colorHex;
  late DateTime createdAt;
  late DateTime targetDate;
  late bool isArchived;
  late int sortOrder;

  @Backlink(to: 'goal')
  final milestones = IsarLinks<Milestone>();
}

// ─────────────────────────────────────────────────────────
// Milestone
// ─────────────────────────────────────────────────────────

@Collection()
class Milestone {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;
  late String title;
  late String theme;
  late DateTime? dueDate;
  late int sortOrder;
  late bool isCollapsed;

  final goal = IsarLink<Goal>();

  @Backlink(to: 'milestone')
  final tasks = IsarLinks<Task>();
}

// ─────────────────────────────────────────────────────────
// Task
// ─────────────────────────────────────────────────────────

@Collection()
class Task {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;
  late String text;
  late bool isCompleted;
  late DateTime? dueDate;
  late int priority; // 0=normal, 1=high, 2=critical
  late String? note;
  late DateTime createdAt;
  late DateTime? completedAt;
  late int sortOrder;

  final milestone = IsarLink<Milestone>();
}

// ─────────────────────────────────────────────────────────
// ScheduleItem
// ─────────────────────────────────────────────────────────

@Collection()
class ScheduleItem {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;
  late String time; // "6:30 AM"
  late String label;
  late String detail;
  late String goalUid; // linked goal uid; empty = no goal
  late List<int> weekdays; // 0=Sun,1=Mon,...,6=Sat
  late bool isActive;
  late int sortOrder;
}
