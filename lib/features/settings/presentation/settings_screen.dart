import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/data_export_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/subscription/entitlements.dart';
import '../../../core/sync/sync_service.dart';
import '../../premium/providers/premium_provider.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../analytics/providers/activity_provider.dart';
import '../providers/backup_provider.dart';
import '../providers/ai_settings_provider.dart';
import '../../habits/providers/habit_provider.dart';
import '../providers/settings_provider.dart';
import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/layout/breakpoints.dart';
import '../../tasks/data/task_repository.dart';
import '../../admin/providers/admin_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text('Settings',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
      ),
      body: AdaptivePage(
        child: settingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (settings) => ListView(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              8,
              context.pageGutter,
              60,
            ),
            children: [
              // ── Account ──────────────────────────────────
              // Identity and sync first: it is the setting most likely to be
              // wanted, and the one that explains why the others travel.
              const _SectionHeader('Account'),
              _NameField(
                initialValue: settings.userName,
                onChanged: notifier.setUserName,
              ),
              const SizedBox(height: 10),
              const _PremiumTile(),
              const _AdminTile(),

              const SizedBox(height: 24),

              // ── Daily habits ─────────────────────────────
              const _SectionHeader('Daily habits'),
              const _HabitsTile(),

              const SizedBox(height: 24),

              // ── Appearance ───────────────────────────────
              const _SectionHeader('Appearance'),
              _ThemeTile(
                current: settings.themeMode,
                onChanged: notifier.setThemeMode,
              ),

              const SizedBox(height: 24),

              // ── Notifications ────────────────────────────
              const _SectionHeader('Notifications'),
              _NotificationTile(
                enabled: settings.dailyReminderEnabled,
                reminderHour: settings.dailyReminderHour,
                reminderMinute: settings.dailyReminderMinute,
                taskDueNotificationsEnabled:
                    settings.taskDueNotificationsEnabled,
                // Each of these does two things: store the preference *and*
                // reschedule the OS notifications. Wiring the setters straight
                // through would save the toggle and leave the alarms wrong.
                onChanged: (value) => _toggleDailyReminder(context, ref, value),
                onReminderTimeChanged: (hour, minute) async {
                  await notifier.setDailyReminderTime(hour, minute);
                  if (settings.dailyReminderEnabled) {
                    await NotificationService.instance.scheduleDailyReminder(
                      hour: hour,
                      minute: minute,
                    );
                  }
                },
                onTaskDueNotificationsChanged: (value) async {
                  await notifier.setTaskDueNotificationsEnabled(value);
                  final tasks = await TaskRepository.instance.getAll();
                  await NotificationService.instance.syncTaskDueNotifications(
                    tasks,
                    enabled: value,
                  );
                },
              ),

              const SizedBox(height: 24),

              // ── AI ───────────────────────────────────────
              const _SectionHeader('AI coach'),
              const _AiConfigurationTile(),

              const SizedBox(height: 24),

              // ── Data ─────────────────────────────────────
              const _SectionHeader('Data'),
              const _BackupSection(),
              const SizedBox(height: 8),
              _ActionTile(
                label: 'Import backup file',
                subtitle: 'Restore from a saved roadmapx_backup.json file.',
                icon: Icons.download_outlined,
                onTap: () => _importFromFile(context, ref),
              ),
              const SizedBox(height: 8),
              _DangerTile(
                label: 'Clear all data',
                subtitle: 'Delete every goal, milestone and task.',
                icon: Icons.delete_forever_outlined,
                color: cs.error,
                onTap: () => _clearAll(context, ref),
              ),

              const SizedBox(height: 24),

              // ── About ────────────────────────────────────
              const _SectionHeader('About'),
              _AboutTile(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final ok1 = await ConfirmationDialog.show(
      context,
      title: 'Clear All Data?',
      message:
          'This will permanently delete all your goals, milestones, tasks and schedule items. This cannot be undone.',
      confirmLabel: 'Delete All',
    );
    if (!ok1 || !context.mounted) return;

    final ok2 = await ConfirmationDialog.show(
      context,
      title: 'Are you absolutely sure?',
      message: 'All data will be erased permanently.',
      confirmLabel: 'Yes, delete everything',
    );
    if (!ok2) return;

    final db = IsarService.instance.db;
    await db.writeTxn(() async {
      await db.goals.clear();
      await db.milestones.clear();
      await db.tasks.clear();
      await db.scheduleItems.clear();
    });

    // Drop notifications scheduled for the records that no longer exist.
    await NotificationService.instance.syncScheduleNotifications(const []);
    await NotificationService.instance
        .syncTaskDueNotifications(const [], enabled: false);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All data cleared.')),
      );
    }
  }

  Future<void> _toggleDailyReminder(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final notifier = ref.read(settingsProvider.notifier);
    final settings = ref.read(settingsProvider).valueOrNull;

    if (enabled) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notification permission is required.'),
            ),
          );
        }
        await notifier.setDailyReminderEnabled(false);
        return;
      }

      await NotificationService.instance.scheduleDailyReminder(
        hour: settings?.dailyReminderHour ?? 9,
        minute: settings?.dailyReminderMinute ?? 0,
      );
      await notifier.setDailyReminderEnabled(true);
      return;
    }

    await NotificationService.instance.cancelDailyReminder();
    await notifier.setDailyReminderEnabled(false);
  }

  Future<void> _importFromFile(BuildContext context, WidgetRef ref) async {
    try {
      // Open system file manager for the user to pick a JSON file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return; // User cancelled

      final pickedFile = result.files.first;
      String? content;

      // file_picker gives bytes on all platforms; on mobile path may also be set
      if (pickedFile.bytes != null) {
        // Backups are written as UTF-8; decoding byte-by-byte would turn
        // every emoji and non-ASCII character into mojibake.
        content = utf8.decode(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        content = await _readFile(pickedFile.path!);
      }

      if (content == null || content.trim().isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected file is empty or unreadable.')),
          );
        }
        return;
      }

      final result2 = await BackupService.instance.withoutScheduling(
        () => DataExportService.instance.importFromJson(content!),
      );
      await BackupService.instance.restorePreferences(result2.preferences);
      // Refresh everything that caches preference-backed state.
      _invalidateRestoredProviders(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${result2.counts.total} records with settings.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  Future<String?> _readFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) return file.readAsString();
    } catch (_) {}
    return null;
  }
}

/// Rebuilds everything a restore or import can change, so the new data is
/// visible immediately instead of after an app restart.
void _invalidateRestoredProviders(WidgetRef ref) {
  ref.invalidate(settingsProvider);
  ref.invalidate(aiSettingsNotifierProvider);
  ref.invalidate(habitsProvider);
  ref.invalidate(todayHabitChecksProvider);
  ref.read(habitActivityTickProvider.notifier).state++;
  bumpActivityTick(ref);
}

/// Admin entry, rendered only for accounts in `public.admins`.
///
/// The server checks this independently on every write, so hiding the tile is
/// a convenience rather than the security boundary.
class _AdminTile extends ConsumerWidget {
  const _AdminTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    if (!isAdmin) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _SettingsSurface(
        child: ListTile(
          leading: Icon(Icons.admin_panel_settings_outlined, color: cs.primary),
          title: const Text(
            'Manage subscriptions',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Activate or revoke other accounts'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push('/admin'),
        ),
      ),
    );
  }
}

/// Entry point to the habits page, with a live count so the section says
/// something even before it is opened.
class _HabitsTile extends ConsumerWidget {
  const _HabitsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final habits = ref.watch(habitsProvider).valueOrNull;
    final count = habits?.length ?? 0;

    return _SettingsSurface(
      child: ListTile(
        leading: Icon(Icons.checklist_rounded, color: cs.primary),
        title: const Text(
          'Non-negotiables',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          count == 0
              ? 'None yet — add the things you do every day'
              : '$count habit${count == 1 ? '' : 's'} tracked daily',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/habits'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Premium / sync entry ──────────────────────────────────

class _PremiumTile extends ConsumerWidget {
  const _PremiumTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isPremium = ref.watch(isPremiumProvider);
    final isAvailable = ref.watch(syncAvailableProvider);
    final status = ref.watch(syncStatusProvider).valueOrNull;

    final String subtitle;
    if (!isAvailable) {
      subtitle = 'Not available in this build — the app stays local';
    } else if (!isPremium) {
      subtitle = 'Keep every device in step. Tap to activate.';
    } else if (status?.stage == SyncStage.syncing) {
      subtitle = 'Syncing…';
    } else if (status?.stage == SyncStage.awaitingFirstSyncChoice) {
      subtitle = 'Choose what to keep before syncing';
    } else if (status?.stage == SyncStage.error) {
      subtitle = 'Sync failed — will retry';
    } else {
      subtitle = 'Active on this device';
    }

    return _SettingsSurface(
      child: ListTile(
        leading: Icon(
          isPremium ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
          color: isPremium ? cs.primary : cs.onSurfaceVariant,
        ),
        title: Text(
          isPremium ? Entitlements.productName : 'Multi-device sync',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/premium'),
      ),
    );
  }
}

/// Material-backed surface for settings cards so ListTile ink/splash renders.
class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: cs.surfaceContainerHighest,
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}

// ── Name field ────────────────────────────────────────────

class _NameField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;
  const _NameField({required this.initialValue, required this.onChanged});

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      final trimmed = _ctrl.text.trim();
      if (trimmed != widget.initialValue) {
        widget.onChanged(trimmed);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _NameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _ctrl.text != widget.initialValue &&
        !_focus.hasFocus) {
      _ctrl.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      focusNode: _focus,
      decoration: const InputDecoration(
        labelText: 'Your Name',
        prefixIcon: Icon(Icons.person_outline),
      ),
      textCapitalization: TextCapitalization.words,
      onFieldSubmitted: (v) => widget.onChanged(v.trim()),
    );
  }
}

// ── Theme tile ────────────────────────────────────────────

class _ThemeTile extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _ThemeTile({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const modes = ['dark', 'light', 'system'];
    const labels = ['Dark', 'Light', 'System'];
    const icons = [
      Icons.dark_mode_outlined,
      Icons.light_mode_outlined,
      Icons.phone_android_outlined
    ];

    return _SettingsSurface(
      child: Column(
        children: List.generate(modes.length, (i) {
          final selected = current == modes[i];
          return ListTile(
            leading: Icon(icons[i],
                color: selected ? cs.primary : cs.onSurfaceVariant),
            title: Text(labels[i]),
            trailing:
                selected ? Icon(Icons.check_circle, color: cs.primary) : null,
            onTap: () => onChanged(modes[i]),
          );
        }),
      ),
    );
  }
}

// ── Non-negotiables editor ────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final bool enabled;
  final int reminderHour;
  final int reminderMinute;
  final bool taskDueNotificationsEnabled;
  final ValueChanged<bool> onChanged;
  final void Function(int hour, int minute) onReminderTimeChanged;
  final ValueChanged<bool> onTaskDueNotificationsChanged;

  const _NotificationTile({
    required this.enabled,
    required this.reminderHour,
    required this.reminderMinute,
    required this.taskDueNotificationsEnabled,
    required this.onChanged,
    required this.onReminderTimeChanged,
    required this.onTaskDueNotificationsChanged,
  });

  void _showTestNotification(BuildContext context) async {
    try {
      await NotificationService.instance.showTestNotification();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test notification sent! Check your device.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    }
  }

  void _showTestScheduledNotification(BuildContext context) async {
    try {
      await NotificationService.instance.showTestScheduledNotification();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scheduled test sent! Should appear in 10 seconds.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scheduled test failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final formattedTime =
        TimeOfDay(hour: reminderHour, minute: reminderMinute).format(context);

    return _SettingsSurface(
      child: Column(
        children: [
          SwitchListTile(
            secondary:
                Icon(Icons.notifications_outlined, color: cs.onSurfaceVariant),
            title: const Text('Daily Reminder'),
            subtitle: const Text('Get a daily nudge to check on your goals.'),
            value: enabled,
            onChanged: onChanged,
          ),
          ListTile(
            leading: Icon(Icons.access_time, color: cs.onSurfaceVariant),
            title: const Text('Reminder time'),
            subtitle: Text(formattedTime),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: reminderHour,
                  minute: reminderMinute,
                ),
              );
              if (picked != null) {
                onReminderTimeChanged(picked.hour, picked.minute);
              }
            },
          ),
          SwitchListTile(
            secondary: Icon(Icons.task_alt, color: cs.onSurfaceVariant),
            title: const Text('Task due notifications'),
            subtitle: const Text('Receive alerts for due and overdue tasks.'),
            value: taskDueNotificationsEnabled,
            onChanged: onTaskDueNotificationsChanged,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showTestNotification(context),
                    icon: const Icon(Icons.notifications_active, size: 18),
                    label: const Text('Test: Immediate Alert'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showTestScheduledNotification(context),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('Test: Scheduled (10 sec)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action tile ───────────────────────────────────────────

class _BackupSection extends ConsumerWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final backupAsync = ref.watch(backupProvider);
    final notifier = ref.read(backupProvider.notifier);
    final isBusy = backupAsync.valueOrNull?.isBusy ?? false;

    return _SettingsSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Backup & Restore',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a backup now or restore the latest backup.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isBusy
                      ? null
                      : () async {
                          final path = await notifier.createBackupNow();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                path == null
                                    ? 'Backup failed.'
                                    : 'Backup saved: $path',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Backup Now'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () async {
                          final mode = await _pickImportMode(context);
                          if (mode == null) return;
                          final counts =
                              await BackupService.instance.withoutScheduling(
                            () => notifier.restoreLatest(mode: mode),
                          );
                          if (!context.mounted) return;
                          if (counts == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('No backup found to restore.')),
                            );
                            return;
                          }
                          // Refresh settings UI with restored values
                          _invalidateRestoredProviders(ref);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Restored ${counts.total} records, ${counts.preferences} preferences.',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('Restore Latest'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            backupAsync.valueOrNull?.lastBackupAt == null
                ? 'No backup created yet.'
                : 'Last backup: ${backupAsync.valueOrNull!.lastBackupAt}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<ImportMode?> _pickImportMode(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    return showAdaptiveSheet<ImportMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Material(
          color: cs.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.merge_type),
                title: const Text('Merge'),
                subtitle:
                    const Text('Keep existing data and add missing records.'),
                onTap: () => Navigator.of(context).pop(ImportMode.merge),
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Replace'),
                subtitle: const Text('Clear existing data then import backup.'),
                onTap: () => Navigator.of(context).pop(ImportMode.replace),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SettingsSurface(
      child: ListTile(
        leading: Icon(icon, color: cs.primary),
        title: Text(label),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

// ── Danger tile ───────────────────────────────────────────

class _DangerTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _DangerTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsSurface(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}

// ── AI config tile ─────────────────────────────────────────

class _AboutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _SettingsSurface(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text('🗺️', style: const TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RoadmapX',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('Version 1.0.0',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              Text('Personal goal & milestone tracker',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
class _AiConfigurationTile extends ConsumerStatefulWidget {
  const _AiConfigurationTile();

  @override
  ConsumerState<_AiConfigurationTile> createState() =>
      _AiConfigurationTileState();
}

class _AiConfigurationTileState extends ConsumerState<_AiConfigurationTile> {
  static const _models = <String, String>{
    'gemini-2.5-flash': 'Gemini 2.5 Flash (Fast, Free tier)',
    'gemini-2.5-pro': 'Gemini 2.5 Pro (Smarter, Slower)',
  };

  late final TextEditingController _apiKeyCtrl = TextEditingController();
  late final FocusNode _focus = FocusNode()..addListener(_commitOnBlur);
  bool _obscure = true;
  bool _hydrated = false;

  @override
  void dispose() {
    _focus.removeListener(_commitOnBlur);
    _focus.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _commitOnBlur() {
    if (_focus.hasFocus) return;
    _commit();
  }

  /// Saves whatever is in the field.
  ///
  /// There is no Save button: a settings screen edits live state, and a button
  /// only adds a way to lose the change by navigating away.
  Future<void> _commit() async {
    final key = _apiKeyCtrl.text.trim();
    final current = ref.read(aiSettingsNotifierProvider).apiKey ?? '';
    if (key == current) return;
    await ref.read(aiSettingsNotifierProvider.notifier).saveApiKey(key);
  }

  Future<void> _clear() async {
    _apiKeyCtrl.clear();
    await ref.read(aiSettingsNotifierProvider.notifier).clearApiKey();
  }

  Future<void> _launchKeyPage() async {
    final uri = Uri.parse('https://aistudio.google.com/app/apikey');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ai = ref.watch(aiSettingsNotifierProvider);
    final notifier = ref.read(aiSettingsNotifierProvider.notifier);
    final hasKey = (ai.apiKey ?? '').isNotEmpty;

    // Seed the field once from storage; after that the field is the source of
    // truth while it is being edited.
    if (!_hydrated && ai.apiKey != null) {
      _hydrated = true;
      _apiKeyCtrl.text = ai.apiKey!;
    }

    return _SettingsSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gemini API key',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (hasKey)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: Color(0xFF34D399)),
                    const SizedBox(width: 4),
                    Text(
                      'Connected',
                      style: tt.labelSmall?.copyWith(
                        color: const Color(0xFF34D399),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Your key stays on this device and is never included in backups '
            'or sync.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyCtrl,
            focusNode: _focus,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'Paste your key',
              prefixIcon: const Icon(Icons.key_outlined, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _obscure ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  if (hasKey)
                    IconButton(
                      tooltip: 'Remove key',
                      icon: Icon(Icons.close_rounded, size: 18, color: cs.error),
                      onPressed: _clear,
                    ),
                ],
              ),
            ),
            onSubmitted: (_) => _commit(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _models.containsKey(ai.model) ? ai.model : null,
            decoration: const InputDecoration(labelText: 'Model'),
            items: [
              for (final entry in _models.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) notifier.saveModel(value);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _launchKeyPage,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Get a free API key'),
            ),
          ),
        ],
      ),
    );
  }
}

