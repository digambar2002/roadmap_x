import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/db/isar_service.dart';
import '../../../core/models/models.dart';
import '../../../core/services/data_export_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../providers/ai_settings_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: Text('Settings',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        backgroundColor: cs.background,
        elevation: 0,
        centerTitle: false,
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
          children: [
            // ── Profile ──────────────────────────────────
            _SectionHeader('Profile').animate().fadeIn(delay: 40.ms),
            _NameField(
              initialValue: settings.userName,
              onChanged: (v) => notifier.setUserName(v),
            ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.05),

            const SizedBox(height: 24),

            // ── Theme ─────────────────────────────────────
            _SectionHeader('Appearance').animate().fadeIn(delay: 100.ms),
            _ThemeTile(
              current: settings.themeMode,
              onChanged: (m) => notifier.setThemeMode(m),
            ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.05),

            const SizedBox(height: 24),

            // ── Non-negotiables ───────────────────────────
            _SectionHeader('Non-Negotiables').animate().fadeIn(delay: 140.ms),
            Text(
              'Daily commitments shown on the dashboard.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ).animate().fadeIn(delay: 160.ms),
            const SizedBox(height: 12),
            _NonNegotiablesEditor(
              values: settings.nonNegotiables,
              onChanged: (list) {
                for (int i = 0; i < list.length; i++) {
                  notifier.setNonNegotiable(i, list[i]);
                }
              },
            ).animate().fadeIn(delay: 180.ms),

            const SizedBox(height: 24),

            // ── Notifications ─────────────────────────────
            _SectionHeader('Notifications').animate().fadeIn(delay: 190.ms),
            _NotificationTile(
              enabled: settings.dailyReminderEnabled,
              onChanged: (value) => _toggleDailyReminder(context, ref, value),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05),

            const SizedBox(height: 24),

            // ── Data ──────────────────────────────────────
            _SectionHeader('Data').animate().fadeIn(delay: 210.ms),
            _ActionTile(
              label: 'Export Data',
              subtitle: 'Save a JSON backup to your device.',
              icon: Icons.upload_outlined,
              onTap: () => _export(context),
            ).animate().fadeIn(delay: 220.ms),
            const SizedBox(height: 8),
            _DangerTile(
              label: 'Clear All Data',
              subtitle: 'Delete all goals, milestones and tasks.',
              icon: Icons.delete_forever_outlined,
              color: cs.error,
              onTap: () => _clearAll(context, ref),
            ).animate().fadeIn(delay: 230.ms),

            const SizedBox(height: 24),

            // ── AI Configuration ──────────────────────────
            _SectionHeader('AI Configuration').animate().fadeIn(delay: 240.ms),
            const _AiConfigurationTile().animate().fadeIn(delay: 250.ms),

            const SizedBox(height: 24),

            // ── About ─────────────────────────────────────
            _SectionHeader('About').animate().fadeIn(delay: 260.ms),
            _AboutTile().animate().fadeIn(delay: 280.ms),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    try {
      final path = await DataExportService.instance.exportToJson();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final ok1 = await ConfirmationDialog.show(
      context,
      title: 'Clear All Data?',
      message:
          'This will permanently delete all your goals, milestones, tasks and schedule items. This cannot be undone.',
      confirmLabel: 'Delete All',
    );
    if (!ok1) return;

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
        hour: 9,
        minute: 0,
      );
      await notifier.setDailyReminderEnabled(true);
      return;
    }

    await NotificationService.instance.cancelDailyReminder();
    await notifier.setDailyReminderEnabled(false);
  }
}

// ── Section header ────────────────────────────────────────

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

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _NameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue &&
        _ctrl.text != widget.initialValue) {
      _ctrl.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      decoration: const InputDecoration(
        labelText: 'Your Name',
        prefixIcon: Icon(Icons.person_outline),
      ),
      textCapitalization: TextCapitalization.words,
      onFieldSubmitted: widget.onChanged,
      onEditingComplete: () => widget.onChanged(_ctrl.text.trim()),
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

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
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

class _NonNegotiablesEditor extends StatefulWidget {
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  const _NonNegotiablesEditor({required this.values, required this.onChanged});

  @override
  State<_NonNegotiablesEditor> createState() => _NonNegotiablesEditorState();
}

class _NonNegotiablesEditorState extends State<_NonNegotiablesEditor> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      4,
      (i) => TextEditingController(
        text: i < widget.values.length ? widget.values[i] : '',
      ),
    );
    for (final c in _controllers) {
      c.addListener(_submit);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.removeListener(_submit);
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    widget.onChanged(_controllers.map((c) => c.text.trim()).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(4, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: _controllers[i],
            decoration: InputDecoration(
              labelText: 'Item ${i + 1}',
              hintText: 'e.g. Exercise, Read, Journal...',
              prefixIcon: const Icon(Icons.check_circle_outline, size: 20),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
        );
      }),
    );
  }
}

// ── Notification tile ─────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _NotificationTile({required this.enabled, required this.onChanged});

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

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
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
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
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

  bool _editing = false;
  bool _obscure = true;
  late final TextEditingController _apiKeyCtrl;

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  String _masked(String key) {
    if (key.length <= 4) return '••••';
    return '••••••••${key.substring(key.length - 4)}';
  }

  Future<void> _launchKeyPage(BuildContext context) async {
    final uri = Uri.parse('https://aistudio.google.com/app/apikey');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ai = ref.watch(aiSettingsNotifierProvider);
    final notifier = ref.read(aiSettingsNotifierProvider.notifier);
    final hasKey = ai.apiKey != null && ai.apiKey!.isNotEmpty;

    if (!_editing && hasKey && _apiKeyCtrl.text != ai.apiKey) {
      _apiKeyCtrl.text = ai.apiKey!;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'AI Configuration',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (hasKey)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34D399).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Color(0xFF34D399)),
                      SizedBox(width: 4),
                      Text('Saved', style: TextStyle(fontSize: 11, color: Color(0xFF34D399))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Gemini API Key',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_editing || !hasKey)
            TextField(
              controller: _apiKeyCtrl,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'Paste your API key',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outline),
              ),
              child: Text(
                _masked(ai.apiKey!),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(letterSpacing: 0.5),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_editing || !hasKey)
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final key = _apiKeyCtrl.text.trim();
                    if (key.isEmpty) return;
                    await notifier.saveApiKey(key);
                    if (mounted) {
                      setState(() => _editing = false);
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: hasKey
                    ? () async {
                        await notifier.clearApiKey();
                        if (mounted) {
                          setState(() {
                            _editing = false;
                            _apiKeyCtrl.clear();
                          });
                        }
                      }
                    : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Model',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _models.containsKey(ai.model) ? ai.model : 'gemini-2.5-flash',
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.psychology_alt_outlined),
            ),
            items: _models.entries
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              notifier.saveModel(value);
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _launchKeyPage(context),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Get free API key'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── About tile ────────────────────────────────────────────

class _AboutTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
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
