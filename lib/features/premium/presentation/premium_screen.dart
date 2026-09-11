import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/subscription/entitlements.dart';
import '../../../core/sync/account_service.dart';
import '../../../core/sync/sync_service.dart';
import '../providers/premium_provider.dart';

class PremiumScreen extends ConsumerWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final account = ref.watch(accountProvider).valueOrNull ??
        AccountService.instance.state;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          Entitlements.productName,
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
        children: [
          const _PerksCard(),
          const SizedBox(height: 24),
          if (!account.isConfigured)
            const _UnavailableCard()
          else if (account.isPremium)
            const _ActiveCard()
          else if (account.isSignedIn)
            _AwaitingActivationCard(account: account)
          else
            _SignInCard(account: account),
          const SizedBox(height: 24),
          Text(
            'Everything else stays free and works offline — your goals, tasks, '
            'schedule, streaks and analytics live on this device whether or '
            'not you ever activate.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
        color: cs.surfaceContainerHighest,
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _PerksCard extends StatelessWidget {
  const _PerksCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What activation adds',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          for (final perk in Entitlements.perks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(perk, style: tt.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This build has no sync backend configured, so accounts are '
              'unavailable. Everything local keeps working.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Signed out ────────────────────────────────────────────

class _SignInCard extends ConsumerStatefulWidget {
  const _SignInCard({required this.account});
  final AccountState account;

  @override
  ConsumerState<_SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends ConsumerState<_SignInCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) return;

    if (_isRegistering) {
      await AccountService.instance.signUp(email, password);
    } else {
      await AccountService.instance.signIn(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final account = widget.account;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isRegistering ? 'Create an account' : 'Sign in',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'An account is only needed for sync. Sign in with the same one on '
            'every device you want kept in step.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              helperText: 'At least 6 characters',
              border: OutlineInputBorder(),
            ),
          ),
          if (account.error != null) ...[
            const SizedBox(height: 12),
            Text(
              account.error!,
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: account.isBusy ? null : _submit,
              child: account.isBusy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isRegistering ? 'Create account' : 'Sign in'),
            ),
          ),
          TextButton(
            onPressed: account.isBusy
                ? null
                : () => setState(() => _isRegistering = !_isRegistering),
            child: Text(
              _isRegistering
                  ? 'I already have an account'
                  : 'I need to create one',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Signed in, not yet activated ──────────────────────────

class _AwaitingActivationCard extends ConsumerWidget {
  const _AwaitingActivationCard({required this.account});
  final AccountState account;

  Future<void> _contact(BuildContext context) async {
    final subject = Uri.encodeComponent('${Entitlements.productName} access');
    final body = Uri.encodeComponent(
      'Hi,\n\nI would like to activate ${Entitlements.productName}.\n\n'
      'My account email: ${account.email ?? ''}\n',
    );
    final uri = Uri.parse(
      'mailto:${Entitlements.supportEmail}?subject=$subject&body=$body',
    );
    if (!await launchUrl(uri) && context.mounted) {
      // Not every desktop or emulator has a mail client registered; the
      // address is on screen and copyable either way.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email ${Entitlements.supportEmail}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not activated yet',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Send us the account email below and we will switch sync on for '
            'you. It usually takes a few hours.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: account.email ?? ''),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Account email copied')),
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      account.email ?? '—',
                      style: tt.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.copy_rounded, size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _contact(context),
              icon: const Icon(Icons.mail_outline_rounded, size: 18),
              label: const Text('Request activation'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final entitled =
                    await AccountService.instance.refreshEntitlement();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      entitled
                          ? 'Activated — sync is starting'
                          : 'Not activated yet',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('I have paid — check again'),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => AccountService.instance.signOut(),
              child: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Active ────────────────────────────────────────────────

class _ActiveCard extends ConsumerWidget {
  const _ActiveCard();

  static String _describe(SyncStatus status) {
    switch (status.stage) {
      case SyncStage.syncing:
        return 'Syncing…';
      case SyncStage.idle:
        final at = status.lastSyncedAt;
        if (at == null) return 'Up to date';
        return 'Last synced ${DateFormat('d MMM, HH:mm').format(at)}';
      case SyncStage.error:
        return status.message ?? 'Sync failed — will retry';
      case SyncStage.inactive:
        return 'Activation is no longer active';
      case SyncStage.signedOut:
        return 'Signed out';
      case SyncStage.unavailable:
        return 'Sync unavailable';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final account = ref.watch(accountProvider).valueOrNull ??
        AccountService.instance.state;
    final status =
        ref.watch(syncStatusProvider).valueOrNull ?? SyncService.instance.status;
    final isError = status.stage == SyncStage.error;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done_rounded, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'Active',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(account.email ?? '', style: tt.bodyMedium),
          const SizedBox(height: 4),
          Text(
            _describe(status),
            style: tt.bodySmall?.copyWith(
              color: isError ? cs.error : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: status.stage == SyncStage.syncing
                  ? null
                  : () => SyncService.instance.syncNow(),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Sync now'),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => AccountService.instance.signOut(),
              child: const Text('Sign out'),
            ),
          ),
          Text(
            'Signing out stops sync. Nothing on this device is removed.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
