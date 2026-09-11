// All Isar data models are defined in this single file
// to avoid cross-file circular import issues with isar_generator.
import 'package:isar_community/isar.dart';

part 'models.g.dart';

// ─────────────────────────────────────────────────────────
// Sync metadata
// ─────────────────────────────────────────────────────────
//
// Every synced row carries three timestamps:
//
//   updatedAt — bumped on every local mutation. The last-writer-wins key:
//               when two devices hold the same uid, the later updatedAt wins.
//   deletedAt — tombstone. Rows are never physically removed while sync is
//               possible, otherwise a peer that hasn't seen the delete would
//               resurrect the row on its next push.
//   syncedAt  — the updatedAt value at the moment the row was last pushed to
//               (or merged from) the server. `syncedAt != updatedAt` means
//               "needs push", which removes the need for a separate outbox
//               table and makes re-pushing idempotent after a crash.
//
// `uid` is the cross-device identity. Isar's autoIncrement `id` is local-only
// and must never leave the device.

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

  /// See [GoalPriority]. Drives what the dashboard surfaces: only Focus goals
  /// get prominence, and Someday goals are kept off it entirely, so a long
  /// list of ambitions does not read as a long list of obligations.
  late int priority;

  @Index()
  late DateTime updatedAt;
  DateTime? deletedAt;
  DateTime? syncedAt;

  @Backlink(to: 'goal')
  final milestones = IsarLinks<Milestone>();
}

/// Priority levels for [Goal].
///
/// Three levels, not five: the point is to make the choice easy enough that
/// people actually make it. Stored as an int so ordering is a plain sort.
class GoalPriority {
  const GoalPriority._();

  /// Parked. Kept out of the dashboard entirely.
  static const int someday = 0;

  /// The default for a new goal.
  static const int active = 1;

  /// What the dashboard leads with.
  static const int focus = 2;

  static const List<int> all = [focus, active, someday];

  static String label(int value) => switch (value) {
        focus => 'Focus',
        someday => 'Someday',
        _ => 'Active',
      };

  static String description(int value) => switch (value) {
        focus => 'Front and centre on the dashboard',
        someday => 'Parked — hidden from the dashboard',
        _ => 'Counted, but not highlighted',
      };

  static int clamp(int? value) {
    if (value == null) return active;
    if (value < someday) return someday;
    if (value > focus) return focus;
    return value;
  }
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

  /// Denormalized parent uid. The IsarLink below is the local query path, but
  /// a row arriving over the wire has no links — it has to carry its own
  /// foreign key to be re-attachable.
  @Index()
  late String goalUid;

  @Index()
  late DateTime updatedAt;
  DateTime? deletedAt;
  DateTime? syncedAt;

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

  /// Denormalized parent uid — see [Milestone.goalUid].
  @Index()
  late String milestoneUid;

  @Index()
  late DateTime updatedAt;
  DateTime? deletedAt;
  DateTime? syncedAt;

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

  @Index()
  late DateTime updatedAt;
  DateTime? deletedAt;
  DateTime? syncedAt;
}

// ─────────────────────────────────────────────────────────
// HabitCheckin
// ─────────────────────────────────────────────────────────

/// A daily non-negotiable the user has defined.
///
/// These were four fixed slots in SharedPreferences. As rows they can be
/// added, renamed, reordered and removed, and they sync like everything else.
@Collection()
class Habit {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;
  late String label;

  /// Key into `HabitIcons.catalog`, not a raw code point.
  ///
  /// Building `IconData` from a stored integer defeats Flutter's icon tree
  /// shaking, which then fails the release build outright. A key into a table
  /// of const IconData keeps every glyph statically reachable.
  late String iconKey;

  late int sortOrder;

  /// A habit is only expected on days at or after this.
  ///
  /// Without it, adding a habit today would retroactively mark every past day
  /// incomplete and wipe out an existing streak.
  late DateTime createdAt;

  @Index()
  late DateTime updatedAt;
  DateTime? deletedAt;
  DateTime? syncedAt;
}

/// One row per (day, habit) rather than one row per day.
///
/// Day-granularity would mean device A ticking one habit and device B ticking
/// another on the same day are two conflicting writes to one row, and
/// last-writer-wins would silently discard one of them. Per-habit rows never
/// collide, so the merge is lossless.
///
/// [uid] is derived (`"2026-09-11#<habitUid>"`), not random: two devices that
/// tick the same habit offline produce the same uid, so they converge on one
/// row instead of creating duplicates.
@Collection()
class HabitCheckin {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;

  @Index()
  late String dayKey; // "2026-09-11"

  @Index()
  late String habitUid;
  late bool isChecked;

  @Index()
  late DateTime updatedAt;
  DateTime? deletedAt;
  DateTime? syncedAt;

  static String uidFor(String dayKey, String habitUid) =>
      '$dayKey#$habitUid';
}

// ─────────────────────────────────────────────────────────
// ScheduleCompletion
// ─────────────────────────────────────────────────────────

/// One row per (day, schedule block) — see [HabitCheckin] for why the
/// granularity and the derived uid matter.
@Collection()
class ScheduleCompletion {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;

  @Index()
  late String dayKey; // "2026-09-11"
  late String scheduleUid;
  late bool isCompleted;

  @Index()
  late DateTime updatedAt;
  DateTime? deletedAt;
  DateTime? syncedAt;

  static String uidFor(String dayKey, String scheduleUid) =>
      '$dayKey#$scheduleUid';
}

// ─────────────────────────────────────────────────────────
// AppSetting
// ─────────────────────────────────────────────────────────

/// A synced preference, one row per key.
///
/// Most of SharedPreferences is device configuration — theme, notification
/// times, permissions — and syncing it would be wrong. A few keys are content:
/// the user's name, and the four non-negotiable labels. Those labels in
/// particular *must* travel, because [HabitCheckin] rows are identified by
/// index: without them a tick made on one device shows up under a different
/// habit on another.
///
/// [uid] is the preference key, so the same setting written on two devices
/// converges on one row instead of duplicating.
@Collection()
class AppSetting {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;

  /// JSON-encoded, so the stored type survives the round trip.
  late String value;

  @Index()
  late DateTime updatedAt;
  DateTime? deletedAt;
  DateTime? syncedAt;
}
