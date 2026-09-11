import 'package:flutter/foundation.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class IsarService {
  IsarService._();
  static final IsarService instance = IsarService._();

  Isar? _isar;

  Isar get db {
    assert(_isar != null, 'IsarService not initialized. Call init() first.');
    return _isar!;
  }

  Future<void> init() async {
    if (_isar != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        GoalSchema,
        MilestoneSchema,
        TaskSchema,
        ScheduleItemSchema,
        HabitSchema,
        HabitCheckinSchema,
        ScheduleCompletionSchema,
        AppSettingSchema,
      ],
      directory: dir.path,
      name: 'roadmap_x',
    );
  }

  /// Points the singleton at a caller-supplied database.
  ///
  /// Tests open Isar in a temp directory; the services and repositories all
  /// reach the database through this singleton, so this is the one seam they
  /// need.
  @visibleForTesting
  void overrideForTesting(Isar isar) => _isar = isar;

  Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}
