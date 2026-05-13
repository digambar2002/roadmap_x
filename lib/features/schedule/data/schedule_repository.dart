import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/notification_service.dart';

class ScheduleRepository {
  ScheduleRepository._();
  static final ScheduleRepository instance = ScheduleRepository._();

  Isar get _db => IsarService.instance.db;
  static const _uuid = Uuid();

  // ── Streams ──────────────────────────────────────────────
  Stream<List<ScheduleItem>> watchAll() => _db.scheduleItems
      .where()
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  Stream<List<ScheduleItem>> watchForWeekday(int weekday) => _db.scheduleItems
      .filter()
      .isActiveEqualTo(true)
      .weekdaysElementEqualTo(weekday)
      .sortBySortOrder()
      .build()
      .watch(fireImmediately: true);

  // ── Reads ─────────────────────────────────────────────────
  Future<List<ScheduleItem>> getAll() =>
      _db.scheduleItems.where().sortBySortOrder().build().findAll();

  Future<ScheduleItem?> getById(int id) => _db.scheduleItems.get(id);

  // ── Writes ────────────────────────────────────────────────
  Future<ScheduleItem> create({
    required String time,
    required String label,
    required String detail,
    required String goalUid,
    required List<int> weekdays,
    bool isActive = true,
  }) async {
    final item = ScheduleItem()
      ..uid = _uuid.v4()
      ..time = time
      ..label = label
      ..detail = detail
      ..goalUid = goalUid
      ..weekdays = weekdays
      ..isActive = isActive
      ..sortOrder = await _nextSortOrder();

    await _db.writeTxn(() async => _db.scheduleItems.put(item));
    await _resyncNotifications();
    return item;
  }

  Future<void> update(ScheduleItem item) async {
    await _db.writeTxn(() async => _db.scheduleItems.put(item));
    await _resyncNotifications();
  }

  Future<void> delete(int id) async {
    await _db.writeTxn(() async => _db.scheduleItems.delete(id));
    await _resyncNotifications();
  }

  Future<int> _nextSortOrder() async {
    final last = await _db.scheduleItems
        .where()
        .sortBySortOrderDesc()
        .limit(1)
        .findFirst();
    return (last?.sortOrder ?? -1) + 1;
  }

  Future<void> _resyncNotifications() async {
    final all = await getAll();
    await NotificationService.instance.syncScheduleNotifications(all);
  }
}
