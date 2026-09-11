import 'dart:async';

import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/isar_service.dart';
import '../models/models.dart';
import '../services/data_export_service.dart';
import '../services/synced_settings.dart';
import 'account_service.dart';
import 'sync_config.dart';

enum SyncStage {
  /// No backend configured in this build — the app is local-only.
  unavailable,

  /// Configured, but nobody is signed in.
  signedOut,

  /// Signed in on a free account. Sync is the paid feature.
  inactive,

  /// First sign-in on a device that already holds data. Syncing would add the
  /// account's rows to the local ones rather than replacing them, so the user
  /// has to say which they meant before anything is written.
  awaitingFirstSyncChoice,

  /// Entitled and up to date.
  idle,

  syncing,

  /// Last attempt failed; local data is untouched and it will retry.
  error,
}

/// What to do with data already on the device when signing in to an account
/// that has its own.
enum FirstSyncChoice {
  /// Keep both sets. Nothing is lost, but near-identical entries made in both
  /// places will both be present.
  mergeBoth,

  /// Discard what is on this device and take the account's copy.
  useAccountData,
}

class SyncStatus {
  const SyncStatus({
    required this.stage,
    this.lastSyncedAt,
    this.pendingCount = 0,
    this.message,
  });

  final SyncStage stage;
  final DateTime? lastSyncedAt;
  final int pendingCount;
  final String? message;
}

/// A local row waiting to be sent.
class _PendingRow {
  const _PendingRow({
    required this.collection,
    required this.uid,
    required this.data,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String collection;
  final String uid;
  final Map<String, dynamic> data;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, dynamic> toPayload(String userId) => {
        'user_id': userId,
        'collection': collection,
        'uid': uid,
        'data': data,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
      };
}

/// Two-way mirror between the local Isar database and Supabase.
///
/// Isar stays the source of truth. Every read the UI performs, and every write
/// the user makes, works whether or not this service ever runs — sync is a
/// background mirror, never something the UI waits on. That is what lets the
/// free tier be the whole app minus this file.
///
/// There is no outbox table. `syncedAt != updatedAt` already identifies a row
/// that needs sending, which makes a retry after a crash or a lost connection
/// idempotent: the same rows are simply found dirty again.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _cursorKey = 'sync_pull_cursor';

  /// Per-account marker: this device has already reconciled with this account,
  /// so later sign-ins go straight to syncing.
  static const _initialisedPrefix = 'sync_initialised_';
  static const _lastSyncedKey = 'sync_last_completed_at';

  /// Server collection names, which double as the keys the snapshot importer
  /// expects, so pulled rows can be fed straight through the same
  /// last-writer-wins merge that file restore uses.
  static const _collections = <String>[
    'goals',
    'milestones',
    'tasks',
    'scheduleItems',
    'habits',
    'habitCheckins',
    'scheduleCompletions',
    'appSettings',
  ];

  /// Rows per upsert request.
  static const _pushChunk = 250;

  /// Rows per pull request.
  ///
  /// Must stay comfortably larger than [_pushChunk]. Postgres `now()` is the
  /// transaction's start time, so every row in one upsert shares a
  /// `server_updated_at`; if more rows carried one timestamp than a page could
  /// hold, the cursor could never advance past it and the pull would stall on
  /// the same page forever.
  static const _pullPage = 1000;

  SharedPreferences? _prefs;
  Timer? _pushTimer;
  Timer? _pullTimer;
  RealtimeChannel? _channel;
  StreamSubscription<AccountState>? _accountSub;
  Future<void>? _inFlight;

  final _controller = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get changes => _controller.stream;

  final _mergedController = StreamController<void>.broadcast();

  /// Fires after a pull has written remote changes into the local database.
  ///
  /// Isar's own watchers cover most of the UI, but the habit and schedule
  /// screens derive their state through cached providers that are invalidated
  /// by hand on local edits. Those have no way to notice a merge without this.
  Stream<void> get merged => _mergedController.stream;

  SyncStatus _status = const SyncStatus(stage: SyncStage.unavailable);
  SyncStatus get status => _status;

  Isar get _db => IsarService.instance.db;
  AccountService get _account => AccountService.instance;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _applyAccountState(_account.state);
    _accountSub = _account.changes.listen((state) {
      _applyAccountState(state);
    });
  }

  void _applyAccountState(AccountState state) {
    if (!state.isConfigured) {
      _emit(const SyncStatus(stage: SyncStage.unavailable));
      _teardownRealtime();
      return;
    }
    if (!state.isSignedIn) {
      _emit(const SyncStatus(stage: SyncStage.signedOut));
      _teardownRealtime();
      return;
    }
    if (!state.isPremium) {
      _emit(SyncStatus(stage: SyncStage.inactive, lastSyncedAt: _lastSyncedAt));
      _teardownRealtime();
      return;
    }
    _setupRealtime(state.userId!);
    unawaited(_beginSync(state.userId!));
  }

  bool _isInitialised(String userId) =>
      _prefs?.getBool('$_initialisedPrefix$userId') ?? false;

  Future<void> _markInitialised(String userId) async {
    await _prefs?.setBool('$_initialisedPrefix$userId', true);
  }

  /// Anything the user could have created before signing in.
  Future<bool> _hasLocalData() async {
    final goals = await _db.goals.filter().deletedAtIsNull().count();
    if (goals > 0) return true;
    final habits = await _db.habits.filter().deletedAtIsNull().count();
    if (habits > 0) return true;
    final schedule = await _db.scheduleItems.filter().deletedAtIsNull().count();
    return schedule > 0;
  }

  /// Starts the first sync for an account, asking first when that would mix
  /// two separate sets of data together.
  Future<void> _beginSync(String userId) async {
    if (!_isInitialised(userId) && await _hasLocalData()) {
      _emit(SyncStatus(
        stage: SyncStage.awaitingFirstSyncChoice,
        lastSyncedAt: _lastSyncedAt,
      ));
      return;
    }
    await _markInitialised(userId);
    await syncNow();
  }

  /// Resolves the first-sign-in question and starts syncing.
  ///
  /// [FirstSyncChoice.useAccountData] deletes what is on this device, which is
  /// the point — it is how someone discards a few things they made while
  /// trying the app out before signing in.
  Future<void> resolveFirstSync(FirstSyncChoice choice) async {
    final userId = _account.state.userId;
    if (userId == null) return;

    if (choice == FirstSyncChoice.useAccountData) {
      await _clearLocalData();
      await resetCursor();
    }
    await _markInitialised(userId);
    await syncNow();
  }

  Future<void> _clearLocalData() async {
    await _db.writeTxn(() async {
      await _db.tasks.clear();
      await _db.milestones.clear();
      await _db.goals.clear();
      await _db.scheduleItems.clear();
      await _db.habitCheckins.clear();
      await _db.habits.clear();
      await _db.scheduleCompletions.clear();
      await _db.appSettings.clear();
    });
  }

  // ── Triggers ──────────────────────────────────────────────

  /// Called from [LocalChanges] after any local mutation. Coalesces a burst of
  /// edits into one request and no-ops entirely for free or offline users.
  void schedulePush() {
    if (!_account.state.canSync) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(SyncConfig.pushDebounce, () => unawaited(syncNow()));
  }

  void _schedulePull() {
    if (!_account.state.canSync) return;
    _pullTimer?.cancel();
    _pullTimer = Timer(SyncConfig.pullDebounce, () => unawaited(syncNow()));
  }

  /// Pull, then push. Serialized: a second call while one is running awaits
  /// the first rather than interleaving two merges over the same rows.
  Future<void> syncNow() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _runSync().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<void> _runSync() async {
    if (!_account.state.canSync) return;
    _emit(SyncStatus(stage: SyncStage.syncing, lastSyncedAt: _lastSyncedAt));

    try {
      // Pull first so that a row the server already has newer is merged before
      // we consider pushing ours; anything of ours that still wins stays dirty
      // and goes out in the push below.
      await _pull();
      await _push();

      final now = DateTime.now();
      await _prefs?.setString(_lastSyncedKey, now.toIso8601String());
      _emit(SyncStatus(stage: SyncStage.idle, lastSyncedAt: now));
    } on PostgrestException catch (error) {
      // RLS refuses every request once the premium flag is off, which is how a
      // lapsed or revoked account stops syncing regardless of what the client
      // believes about its own entitlement.
      final entitled = await _account.refreshEntitlement();
      if (!entitled) {
        _emit(SyncStatus(
          stage: SyncStage.inactive,
          lastSyncedAt: _lastSyncedAt,
        ));
        return;
      }
      _emit(SyncStatus(
        stage: SyncStage.error,
        lastSyncedAt: _lastSyncedAt,
        message: error.message,
      ));
    } catch (error) {
      _emit(SyncStatus(
        stage: SyncStage.error,
        lastSyncedAt: _lastSyncedAt,
        message: error.toString(),
      ));
    }
  }

  // ── Push ──────────────────────────────────────────────────

  static bool _isDirty(DateTime updatedAt, DateTime? syncedAt) =>
      syncedAt == null || syncedAt.isBefore(updatedAt);

  Future<void> _push() async {
    final userId = _account.state.userId;
    if (userId == null) return;

    final pending = await _collectDirty();
    if (pending.isEmpty) return;

    for (var start = 0; start < pending.length; start += _pushChunk) {
      final end =
          start + _pushChunk < pending.length ? start + _pushChunk : pending.length;
      final chunk = pending.sublist(start, end);

      await _account.client.from(SyncConfig.recordsTable).upsert(
            chunk.map((row) => row.toPayload(userId)).toList(),
            onConflict: 'user_id,collection,uid',
          );

      // Marked per chunk, so an interrupted push keeps the work it completed
      // instead of re-sending everything next time.
      final confirmed = <String, Map<String, DateTime>>{};
      for (final row in chunk) {
        confirmed.putIfAbsent(row.collection, () => {})[row.uid] = row.updatedAt;
      }
      await _markSynced(confirmed);
    }
  }

  Future<List<_PendingRow>> _collectDirty() async {
    final rows = <_PendingRow>[];

    for (final row in await _db.goals.where().build().findAll()) {
      if (!_isDirty(row.updatedAt, row.syncedAt)) continue;
      rows.add(_PendingRow(
        collection: 'goals',
        uid: row.uid,
        data: DataExportService.goalToMap(row),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      ));
    }
    for (final row in await _db.milestones.where().build().findAll()) {
      if (!_isDirty(row.updatedAt, row.syncedAt)) continue;
      rows.add(_PendingRow(
        collection: 'milestones',
        uid: row.uid,
        data: DataExportService.milestoneToMap(row),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      ));
    }
    for (final row in await _db.tasks.where().build().findAll()) {
      if (!_isDirty(row.updatedAt, row.syncedAt)) continue;
      rows.add(_PendingRow(
        collection: 'tasks',
        uid: row.uid,
        data: DataExportService.taskToMap(row),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      ));
    }
    for (final row in await _db.scheduleItems.where().build().findAll()) {
      if (!_isDirty(row.updatedAt, row.syncedAt)) continue;
      rows.add(_PendingRow(
        collection: 'scheduleItems',
        uid: row.uid,
        data: DataExportService.scheduleItemToMap(row),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      ));
    }
    for (final row in await _db.habits.where().build().findAll()) {
      if (!_isDirty(row.updatedAt, row.syncedAt)) continue;
      rows.add(_PendingRow(
        collection: 'habits',
        uid: row.uid,
        data: DataExportService.habitToMap(row),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      ));
    }
    for (final row in await _db.habitCheckins.where().build().findAll()) {
      if (!_isDirty(row.updatedAt, row.syncedAt)) continue;
      rows.add(_PendingRow(
        collection: 'habitCheckins',
        uid: row.uid,
        data: DataExportService.habitCheckinToMap(row),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      ));
    }
    for (final row in await _db.scheduleCompletions.where().build().findAll()) {
      if (!_isDirty(row.updatedAt, row.syncedAt)) continue;
      rows.add(_PendingRow(
        collection: 'scheduleCompletions',
        uid: row.uid,
        data: DataExportService.scheduleCompletionToMap(row),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      ));
    }

    for (final row in await _db.appSettings.where().build().findAll()) {
      if (!_isDirty(row.updatedAt, row.syncedAt)) continue;
      rows.add(_PendingRow(
        collection: 'appSettings',
        uid: row.uid,
        data: DataExportService.appSettingToMap(row),
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
      ));
    }

    return rows;
  }

  // ── Pull ──────────────────────────────────────────────────

  Future<void> _pull() async {
    final userId = _account.state.userId;
    if (userId == null) return;

    var cursor = _pullCursor;
    var newest = cursor;

    while (true) {
      var query = _account.client
          .from(SyncConfig.recordsTable)
          .select('collection, uid, data, updated_at, deleted_at, '
              'server_updated_at')
          .eq('user_id', userId);

      if (cursor != null) {
        query = query.gt(
          'server_updated_at',
          cursor.subtract(SyncConfig.pullOverlap).toUtc().toIso8601String(),
        );
      }

      final page = await query
          .order('server_updated_at', ascending: true)
          .limit(_pullPage);
      if (page.isEmpty) break;

      await _mergePage(page);

      for (final row in page) {
        final stamp = DateTime.tryParse(
          (row['server_updated_at'] ?? '').toString(),
        );
        if (stamp == null) continue;
        if (newest == null || stamp.isAfter(newest)) newest = stamp;
      }

      if (page.length < _pullPage) break;

      // No forward progress means the whole page sat inside the overlap
      // window; stop rather than request it forever.
      if (newest == null || (cursor != null && !newest.isAfter(cursor))) break;
      cursor = newest;
    }

    if (newest != null) {
      await _prefs?.setString(_cursorKey, newest.toUtc().toIso8601String());
    }
  }

  /// Feeds a page of server rows through the same merge the file importer
  /// uses, then records which of them the merge accepted.
  Future<void> _mergePage(List<Map<String, dynamic>> page) async {
    final grouped = <String, List<dynamic>>{
      for (final collection in _collections) collection: <dynamic>[],
    };
    final incoming = <String, Map<String, DateTime>>{};

    for (final row in page) {
      final collection = (row['collection'] ?? '').toString();
      final bucket = grouped[collection];
      if (bucket == null) continue;

      final data = row['data'];
      if (data is! Map) continue;
      final map = Map<String, dynamic>.from(data);

      // The server columns are authoritative over anything stale embedded in
      // the JSON blob.
      map['updatedAt'] = row['updated_at'];
      map['deletedAt'] = row['deleted_at'];
      bucket.add(map);

      final uid = (row['uid'] ?? map['uid'] ?? '').toString();
      final updatedAt =
          DateTime.tryParse((row['updated_at'] ?? '').toString());
      if (uid.isEmpty || updatedAt == null) continue;
      incoming.putIfAbsent(collection, () => {})[uid] = updatedAt;
    }

    final result = await DataExportService.instance.importFromMap(
      {'version': DataExportService.formatVersion, ...grouped},
      mode: ImportMode.merge,
    );

    await _markSynced(incoming);

    if (result.counts.total > 0 && !_mergedController.isClosed) {
      _mergedController.add(null);
    }

    // Settings live in SharedPreferences at read time; a merged row only takes
    // effect once written back there.
    if (_prefs != null && (grouped['appSettings']?.isNotEmpty ?? false)) {
      await SyncedSettings.instance.hydrate(_prefs!);
    }
  }

  // ── Watermarks ────────────────────────────────────────────

  /// Stamps `syncedAt` on rows that are now in agreement with the server.
  ///
  /// A row is only marked when its local `updatedAt` is no newer than the
  /// value that changed hands. If the user edited it in between — or the merge
  /// rejected the server's copy because the local one was newer — it stays
  /// dirty and goes out on the next push.
  Future<void> _markSynced(Map<String, Map<String, DateTime>> confirmed) async {
    if (confirmed.isEmpty) return;

    await _db.writeTxn(() async {
      for (final entry in confirmed.entries) {
        final uids = entry.value;
        if (uids.isEmpty) continue;
        final keys = uids.keys.toList();

        switch (entry.key) {
          case 'goals':
            final rows = await _db.goals
                .filter()
                .anyOf(keys, (q, uid) => q.uidEqualTo(uid))
                .findAll();
            final touched = <Goal>[];
            for (final row in rows) {
              if (row.updatedAt.isAfter(uids[row.uid]!)) continue;
              row.syncedAt = row.updatedAt;
              touched.add(row);
            }
            if (touched.isNotEmpty) await _db.goals.putAll(touched);

          case 'milestones':
            final rows = await _db.milestones
                .filter()
                .anyOf(keys, (q, uid) => q.uidEqualTo(uid))
                .findAll();
            final touched = <Milestone>[];
            for (final row in rows) {
              if (row.updatedAt.isAfter(uids[row.uid]!)) continue;
              row.syncedAt = row.updatedAt;
              touched.add(row);
            }
            if (touched.isNotEmpty) await _db.milestones.putAll(touched);

          case 'tasks':
            final rows = await _db.tasks
                .filter()
                .anyOf(keys, (q, uid) => q.uidEqualTo(uid))
                .findAll();
            final touched = <Task>[];
            for (final row in rows) {
              if (row.updatedAt.isAfter(uids[row.uid]!)) continue;
              row.syncedAt = row.updatedAt;
              touched.add(row);
            }
            if (touched.isNotEmpty) await _db.tasks.putAll(touched);

          case 'scheduleItems':
            final rows = await _db.scheduleItems
                .filter()
                .anyOf(keys, (q, uid) => q.uidEqualTo(uid))
                .findAll();
            final touched = <ScheduleItem>[];
            for (final row in rows) {
              if (row.updatedAt.isAfter(uids[row.uid]!)) continue;
              row.syncedAt = row.updatedAt;
              touched.add(row);
            }
            if (touched.isNotEmpty) await _db.scheduleItems.putAll(touched);

          case 'habits':
            final rows = await _db.habits
                .filter()
                .anyOf(keys, (q, uid) => q.uidEqualTo(uid))
                .findAll();
            final touched = <Habit>[];
            for (final row in rows) {
              if (row.updatedAt.isAfter(uids[row.uid]!)) continue;
              row.syncedAt = row.updatedAt;
              touched.add(row);
            }
            if (touched.isNotEmpty) await _db.habits.putAll(touched);

          case 'habitCheckins':
            final rows = await _db.habitCheckins
                .filter()
                .anyOf(keys, (q, uid) => q.uidEqualTo(uid))
                .findAll();
            final touched = <HabitCheckin>[];
            for (final row in rows) {
              if (row.updatedAt.isAfter(uids[row.uid]!)) continue;
              row.syncedAt = row.updatedAt;
              touched.add(row);
            }
            if (touched.isNotEmpty) await _db.habitCheckins.putAll(touched);

          case 'scheduleCompletions':
            final rows = await _db.scheduleCompletions
                .filter()
                .anyOf(keys, (q, uid) => q.uidEqualTo(uid))
                .findAll();
            final touched = <ScheduleCompletion>[];
            for (final row in rows) {
              if (row.updatedAt.isAfter(uids[row.uid]!)) continue;
              row.syncedAt = row.updatedAt;
              touched.add(row);
            }
            if (touched.isNotEmpty) {
              await _db.scheduleCompletions.putAll(touched);
            }

          case 'appSettings':
            final rows = await _db.appSettings
                .filter()
                .anyOf(keys, (q, uid) => q.uidEqualTo(uid))
                .findAll();
            final touched = <AppSetting>[];
            for (final row in rows) {
              if (row.updatedAt.isAfter(uids[row.uid]!)) continue;
              row.syncedAt = row.updatedAt;
              touched.add(row);
            }
            if (touched.isNotEmpty) await _db.appSettings.putAll(touched);
        }
      }
    });
  }

  DateTime? get _pullCursor {
    final raw = _prefs?.getString(_cursorKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  DateTime? get _lastSyncedAt {
    final raw = _prefs?.getString(_lastSyncedKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Forgets the pull cursor so the next sync re-reads the account from
  /// scratch. Used when adding a device, and as the recovery path if a merge
  /// ever looks wrong.
  Future<void> resetCursor() async {
    await _prefs?.remove(_cursorKey);
  }

  // ── Realtime ──────────────────────────────────────────────

  void _setupRealtime(String userId) {
    if (_channel != null) return;
    _channel = _account.client
        .channel('records:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SyncConfig.recordsTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          // The payload is deliberately ignored in favour of a cursor-driven
          // pull: a dropped or out-of-order event then costs nothing, because
          // the next pull reads everything newer than the cursor regardless.
          callback: (_) => _schedulePull(),
        )
        .subscribe();
  }

  void _teardownRealtime() {
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_account.client.removeChannel(channel));
  }

  void _emit(SyncStatus next) {
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Future<void> dispose() async {
    _pushTimer?.cancel();
    _pullTimer?.cancel();
    _teardownRealtime();
    await _accountSub?.cancel();
    await _controller.close();
    await _mergedController.close();
  }
}
