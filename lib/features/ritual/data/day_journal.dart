import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/habit_checkin_service.dart';
import '../../../core/services/local_changes.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../../core/services/synced_settings.dart';

/// One evening's wrap-up: how the day felt and a line about it.
class DayNote {
  const DayNote({required this.mood, required this.note, required this.at});

  /// 1 (rough) … 5 (great).
  final int mood;
  final String note;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'mood': mood, 'note': note, 'at': at.toIso8601String()};

  static DayNote? fromJson(Object? json) {
    if (json is! Map) return null;
    final mood = (json['mood'] as num?)?.toInt();
    if (mood == null) return null;
    return DayNote(
      mood: mood.clamp(1, 5),
      note: '${json['note'] ?? ''}',
      at: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
    );
  }
}

/// The daily rituals' memory: each day's top 3 (task uids) and each
/// evening's note. One JSON setting on the synced list, so it follows the
/// account across devices.
class DayJournal {
  const DayJournal({this.plans = const {}, this.notes = const {}});

  static const key = 'day_journal_v1';

  /// dayKey → planned task uids, in order.
  final Map<String, List<String>> plans;

  /// dayKey → the evening note.
  final Map<String, DayNote> notes;

  static String dayKey(DateTime d) => HabitCheckinService.dayKeyFor(d);

  List<String> topFor(DateTime day) => plans[dayKey(day)] ?? const [];
  bool hasPlanned(DateTime day) => plans.containsKey(dayKey(day));
  DayNote? noteFor(DateTime day) => notes[dayKey(day)];
  bool hasWrappedUp(DateTime day) => notes.containsKey(dayKey(day));

  static DayJournal read(SharedPreferences prefs) {
    final raw = prefs.getString(key);
    if (raw == null) return const DayJournal();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return DayJournal(
        plans: {
          for (final e in ((json['plans'] as Map?) ?? const {}).entries)
            '${e.key}': [for (final u in (e.value as List)) '$u'],
        },
        notes: {
          for (final e in ((json['notes'] as Map?) ?? const {}).entries)
            if (DayNote.fromJson(e.value) case final n?) '${e.key}': n,
        },
      );
    } catch (_) {
      return const DayJournal();
    }
  }

  Map<String, dynamic> toJson() => {
        'plans': plans,
        'notes': {for (final e in notes.entries) e.key: e.value.toJson()},
      };
}

class DayJournalNotifier extends Notifier<DayJournal> {
  late SharedPreferences _prefs;

  @override
  DayJournal build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    final sub =
        SyncedSettings.instance.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(sub.cancel);
    return DayJournal.read(_prefs);
  }

  Future<void> _save(DayJournal next) async {
    // Keep plans for the last ~2 months and notes for a year; that is what
    // the rituals and insights use, and it keeps the synced blob small.
    final now = DateTime.now();
    final planCutoff =
        DayJournal.dayKey(DateTime(now.year, now.month, now.day - 60));
    final noteCutoff =
        DayJournal.dayKey(DateTime(now.year - 1, now.month, now.day));
    final pruned = DayJournal(
      plans: {
        for (final e in next.plans.entries)
          if (e.key.compareTo(planCutoff) >= 0) e.key: e.value,
      },
      notes: {
        for (final e in next.notes.entries)
          if (e.key.compareTo(noteCutoff) >= 0) e.key: e.value,
      },
    );
    state = pruned;
    await _prefs.setString(DayJournal.key, jsonEncode(pruned.toJson()));
    await SyncedSettings.instance.capture(_prefs, DayJournal.key);
    unawaited(LocalChanges.instance.notify());
  }

  Future<void> setTop(DateTime day, List<String> taskUids) => _save(DayJournal(
        plans: {...state.plans, DayJournal.dayKey(day): taskUids},
        notes: state.notes,
      ));

  Future<void> saveNote(DateTime day,
          {required int mood, required String note}) =>
      _save(DayJournal(
        plans: state.plans,
        notes: {
          ...state.notes,
          DayJournal.dayKey(day):
              DayNote(mood: mood, note: note.trim(), at: DateTime.now()),
        },
      ));
}

final dayJournalProvider =
    NotifierProvider<DayJournalNotifier, DayJournal>(DayJournalNotifier.new);
