import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/tasks/data/task_repository.dart';

import '../db/isar_service.dart';

/// Top-level background callback invoked by HomeWidget when interactive button is clicked
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;
  try {
    if (uri.host == 'complete' || uri.path.contains('complete')) {
      final taskIdStr = uri.queryParameters['taskId'];
      if (taskIdStr != null) {
        final taskId = int.tryParse(taskIdStr);
        if (taskId != null) {
          await IsarService.instance.init();
          final task = await TaskRepository.instance.getById(taskId);
          if (task != null && !task.isCompleted) {
            await TaskRepository.instance.toggleComplete(taskId);
          }
        }
      }
    }
  } catch (e) {
    debugPrint('widgetBackgroundCallback error: $e');
  }
}

class WidgetSyncService {
  WidgetSyncService._();
  static final instance = WidgetSyncService._();

  static const String _widgetProviderName = 'TodayTasksWidgetProvider';

  static bool get isSupported {
    if (kIsWeb) return false;
    try {
      // ServicesBinding.instance throws if binding hasn't been initialized (e.g. pure unit tests)
      ServicesBinding.instance;
    } catch (_) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// Process any task completions marked on the Android widget while app was in background
  Future<void> processPendingCompletions() async {
    if (!isSupported) return;
    try {
      final pendingStr =
          await HomeWidget.getWidgetData<String>('pending_completed_task_ids');
      if (pendingStr != null && pendingStr.isNotEmpty && pendingStr != '[]') {
        final rawList = jsonDecode(pendingStr) as List;
        final ids = rawList.map((e) => (e as num).toInt()).toList();
        if (ids.isNotEmpty) {
          await HomeWidget.saveWidgetData<String>(
              'pending_completed_task_ids', '[]');
          for (final id in ids) {
            final task = await TaskRepository.instance.getById(id);
            if (task != null && !task.isCompleted) {
              await TaskRepository.instance.toggleComplete(id);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('processPendingCompletions error: $e');
    }
  }

  /// Synchronize today's tasks from the database to the Android Home Screen Widget.
  Future<void> syncTodayTasks() async {
    if (!isSupported) return;

    try {
      await processPendingCompletions();
      final contexts = await TaskRepository.instance.getActiveTaskContexts();

      // Categorize tasks similarly to TodayScreen
      final overdue = <Map<String, dynamic>>[];
      final dueToday = <Map<String, dynamic>>[];
      final thisWeek = <Map<String, dynamic>>[];
      final other = <Map<String, dynamic>>[];

      final timeFormat = DateFormat('h:mm a');
      final dayFormat = DateFormat('EEE');

      for (final ctx in contexts) {
        if (ctx.task.isCompleted) continue;

        String dueFormatted = '';
        if (ctx.dueDate != null) {
          final due = ctx.dueDate!;
          if (ctx.isOverdue) {
            dueFormatted = 'Overdue';
          } else if (ctx.isDueToday) {
            // If it has non-zero hour/minute, show time, else "Today"
            if (due.hour != 0 || due.minute != 0) {
              dueFormatted = timeFormat.format(due);
            } else {
              dueFormatted = 'Today';
            }
          } else if (ctx.isDueThisWeek) {
            dueFormatted = dayFormat.format(due);
          } else {
            dueFormatted = DateFormat('MMM d').format(due);
          }
        }

        final item = {
          'id': ctx.task.id,
          'title': ctx.task.text.trim(),
          'goalTitle': ctx.goal?.name.trim() ?? ctx.milestone?.title.trim() ?? '',
          'isOverdue': ctx.isOverdue,
          'isDueToday': ctx.isDueToday,
          'dueDateFormatted': dueFormatted,
        };

        if (ctx.isOverdue) {
          overdue.add(item);
        } else if (ctx.isDueToday) {
          dueToday.add(item);
        } else if (ctx.isDueThisWeek) {
          thisWeek.add(item);
        } else {
          other.add(item);
        }
      }

      // Prioritized list of tasks: Overdue -> Today -> This Week -> Other
      final orderedTasks = [
        ...overdue,
        ...dueToday,
        ...thisWeek,
        ...other,
      ];

      final actionableCount = overdue.length + dueToday.length + thisWeek.length;
      final dateFormatted = DateFormat('EEE, MMM d').format(DateTime.now());
      final tasksJson = jsonEncode(orderedTasks);

      await HomeWidget.saveWidgetData<String>('tasks_json', tasksJson);
      await HomeWidget.saveWidgetData<int>('task_count', actionableCount);
      await HomeWidget.saveWidgetData<String>('date_formatted', dateFormatted);

      await HomeWidget.updateWidget(
        name: _widgetProviderName,
        androidName: _widgetProviderName,
      );
    } on MissingPluginException {
      // Ignored in headless test environments where home_widget channel is not registered.
      return;
    } catch (e, stack) {
      debugPrint('WidgetSyncService error: $e\n$stack');
    }
  }

  /// Check if app was initially opened from home widget click and listen for clicks.
  Future<void> initLaunchListener(void Function(Uri uri) onUri) async {
    if (!isSupported) return;

    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);

      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialUri != null) {
        onUri(initialUri);
      }

      HomeWidget.widgetClicked.listen((uri) {
        if (uri != null) {
          onUri(uri);
        }
      });
    } catch (e) {
      debugPrint('HomeWidget launch listener error: $e');
    }
  }
}
