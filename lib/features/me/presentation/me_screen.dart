import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/subscription/entitlements.dart';
import '../../../core/sync/account_service.dart';
import '../../../core/sync/sync_service.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../admin/providers/admin_provider.dart';
import '../../habits/providers/habit_provider.dart';
import '../../premium/providers/premium_provider.dart';
import '../../settings/providers/settings_provider.dart';

/// The "Me" tab: one place for who you are and everything about the app.
///
/// Before this, sign-in was a small icon on Home, settings was a gear on the
/// Goals screen, and the schedule was a link inside Settings. All of it lives
/// here now, in the order people look for it: identity and plan first, then
/// the tools, then the app's own settings.
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final signedIn =
        ref.watch(accountProvider).valueOrNull?.isSignedIn ?? false;

    return Scaffold(
      backgroundColor: cs.surface,
      body: AdaptivePage(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              context.pageGutter,
              20,
              context.pageGutter,
              40,
            ),
            children: [
              Text(
                'Me',
                style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const _ProfileCard(),
              const SizedBox(height: 12),
              const _PlanCard(),
              const SizedBox(height: 24),
              const _GroupLabel('Plan & progress'),
              _Group(
                children: [
                  _Row(
                    icon: Icons.insights_rounded,
                    title: 'Insights',
                    subtitle: 'Streaks, completion and goal progress',
                    onTap: () => context.push('/analytics'),
                  ),
                  _Row(
                    icon: Icons.calendar_month_rounded,
                    title: 'Schedule & routines',
                    subtitle: 'Your weekly time blocks',
                    onTap: () => context.push('/schedule'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _GroupLabel('App'),
              _Group(
                children: [
                  _Row(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Notifications, appearance, AI coach, backup',
                    onTap: () => context.push('/settings'),
                  ),
                  if (isAdmin)
                    _Row(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Manage subscriptions',
                      subtitle: 'Activate or revoke accounts',
                      onTap: () => context.push('/admin'),
                    ),
                  _Row(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & feedback',
                    subtitle: 'Email the developer',
                    onTap: () => _emailSupport(context),
                  ),
                ],
              ),
              if (signedIn) ...[
                const SizedBox(height: 24),
                _Group(
                  children: [
                    _Row(
                      icon: Icons.logout_rounded,
                      title: 'Sign out',
                      subtitle: 'Your data stays on this device',
                      destructive: true,
                      showChevron: false,
                      onTap: () => _signOut(context),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _emailSupport(BuildContext context) async {
    final uri = Uri.parse(
      'mailto:${Entitlements.supportEmail}?subject=RoadmapX%20feedback',
    );
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email ${Entitlements.supportEmail}')),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await ConfirmationDialog.show(
      context,
      title: 'Sign out?',
      message: 'Sync stops on this device. Everything already here stays.',
      confirmLabel: 'Sign out',
    );
    if (ok) await AccountService.instance.signOut();
  }
}

// ── Profile ───────────────────────────────────────────────

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final account = ref.watch(accountProvider).valueOrNull;
    final habits = ref.watch(habitsProvider).valueOrNull?.length ?? 0;
    final streak = ref.watch(habitStreakProvider).valueOrNull ?? 0;

    final rawName = settings?.userName ?? '';
    final name = rawName.isEmpty || rawName == 'there' ? null : rawName;
    final email = account?.email;
    final display = name ?? email ?? 'Add your name';
    final initialSource = name ?? email ?? '';
    final initial = initialSource.isEmpty
        ? '?'
        : initialSource.characters.first.toUpperCase();

    return _Surface(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _editName(context, ref, name ?? ''),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: cs.primary.withValues(alpha: 0.15),
                child: Text(
                  initial,
                  style: tt.titleLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: name == null && email == null
                            ? cs.onSurfaceVariant
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name != null && email != null
                          ? email
                          : '$habits habit${habits == 1 ? '' : 's'} · '
                              '$streak day streak',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration:
              const InputDecoration(hintText: 'What should we call you?'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final trimmed = result.trim();
    await ref
        .read(settingsProvider.notifier)
        .setUserName(trimmed.isEmpty ? 'there' : trimmed);
  }
}

// ── Account & plan ────────────────────────────────────────

/// Sign-in and Premium as one card, because for the user they are one
/// question: "is my data backed up and on my other devices?"
class _PlanCard extends ConsumerWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final available = ref.watch(syncAvailableProvider);
    final account = ref.watch(accountProvider).valueOrNull;
    final isPremium = ref.watch(isPremiumProvider);
    final status = ref.watch(syncStatusProvider).valueOrNull;

    if (!available) return const SizedBox.shrink();

    final signedIn = account?.isSignedIn ?? false;

    final IconData icon;
    final String title;
    final String body;
    final String? cta;

    if (!signedIn) {
      icon = Icons.cloud_upload_outlined;
      title = 'Back up and sync';
      body = 'Sign in to keep your goals safe in the cloud and on every '
          'device. Everything works offline without an account.';
      cta = 'Sign in';
    } else if (!isPremium) {
      icon = Icons.workspace_premium_outlined;
      title = 'Upgrade to Premium';
      body = 'Cloud backup, sync across devices, unlimited goals and the AI '
          'coach.';
      cta = 'See Premium';
    } else {
      icon = Icons.cloud_done_rounded;
      title = Entitlements.productName;
      body = switch (status?.stage) {
        SyncStage.syncing => 'Syncing…',
        SyncStage.awaitingFirstSyncChoice =>
          'Choose what to keep before syncing starts.',
        SyncStage.error => 'Last sync failed. It will retry automatically.',
        _ => 'Backed up and in sync on this device.',
      };
      cta = null;
    }

    return _Surface(
      highlighted: !isPremium,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/premium'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (cta != null)
                FilledButton.tonal(
                  onPressed: () => context.push('/premium'),
                  child: Text(cta),
                )
              else
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Building blocks ───────────────────────────────────────

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.highlighted = false});
  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: highlighted
          ? cs.primary.withValues(alpha: 0.06)
          : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlighted ? cs.primary.withValues(alpha: 0.35) : cs.outline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Surface(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: cs.outline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.onSurface;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: destructive ? cs.error : cs.primary),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: showChevron
          ? Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant)
          : null,
    );
  }
}
