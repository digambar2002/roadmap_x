import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/subscription/entitlements.dart';
import '../../../core/sync/account_service.dart';
import '../../../core/sync/sync_service.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../providers/premium_provider.dart';

/// The account screen: sign in, see your plan, and upgrade.
///
/// Signing in is free and is only about your account. Premium is a separate,
/// clearly labelled step on the same screen once you are signed in, so the
/// sign-in page never reads like a payment page.
class PremiumScreen extends ConsumerWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final account =
        ref.watch(accountProvider).valueOrNull ?? AccountService.instance.state;
    final signedIn = account.isConfigured && account.isSignedIn;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          signedIn ? 'Account' : 'Sign in',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
      ),
      body: AdaptivePage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            if (!account.isConfigured)
              const _UnavailableCard()
            else if (!signedIn)
              _SignInView(account: account)
            else ...[
              _AccountHeader(account: account),
              const SizedBox(height: 16),
              const _FirstSyncChoiceCard(),
              if (account.isPremium)
                const _SyncCard()
              else
                _UpgradeCard(account: account),
              const SizedBox(height: 20),
              _SignOutButton(premium: account.isPremium),
            ],
          ],
        ),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
        color: cs.surfaceContainerHighest,
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

// ── What Premium adds ─────────────────────────────────────

const _perks = <(IconData, String, String)>[
  (
    Icons.devices_rounded,
    'Sync across devices',
    'Phone, tablet and laptop always in step'
  ),
  (
    Icons.cloud_done_outlined,
    'Cloud backup',
    'Restore everything onto a new phone in seconds'
  ),
  (
    Icons.auto_awesome,
    'AI coach and planning',
    'Briefings, reviews and AI-built plans, no API key needed'
  ),
  (
    Icons.all_inclusive_rounded,
    'Unlimited goals',
    'The free plan keeps ${Entitlements.freeActiveGoalLimit} goals active'
  ),
];

class _PerkList extends StatelessWidget {
  const _PerkList({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final (icon, title, subtitle) in _perks)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 8 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 30 : 36,
                  height: compact ? 30 : 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: compact ? 16 : 19, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (!compact)
                        Text(subtitle,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Signed out: sign in / create account ──────────────────

class _SignInView extends ConsumerStatefulWidget {
  const _SignInView({required this.account});
  final AccountState account;

  @override
  ConsumerState<_SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends ConsumerState<_SignInView> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _showPassword = false;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _submit() async {
    setState(() => _notice = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    if (_creating) {
      final signedIn =
          await AccountService.instance.signUp(email, _password.text);
      if (signedIn == false && mounted) {
        setState(() {
          _creating = false;
          _notice = 'Almost there: we sent a confirmation link to $email. '
              'Open it, then sign in here.';
        });
      }
    } else {
      await AccountService.instance.signIn(email, _password.text);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() =>
          _notice = 'Enter your email above, then tap "Forgot password?".');
      return;
    }
    final sent = await AccountService.instance.sendPasswordReset(email);
    if (sent && mounted) {
      setState(
          () => _notice = 'Check $email for a link to reset your password.');
    }
  }

  void _switchMode(bool creating) {
    AccountService.instance.clearError();
    setState(() {
      _creating = creating;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final account = widget.account;
    final busy = account.isBusy;

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 76,
                height: 76,
                errorBuilder: (_, __, ___) =>
                    const Text('🧭', style: TextStyle(fontSize: 56)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your plan, on every device',
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in to keep your goals and habits safe and pick up where you '
            'left off on any phone.',
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // Google first: one tap, no password to remember.
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: busy
                  ? null
                  : () => AccountService.instance.signInWithGoogle(),
              style: OutlinedButton.styleFrom(
                backgroundColor: cs.surface,
                side: BorderSide(color: cs.outline),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleMark(),
                  const SizedBox(width: 12),
                  Text('Continue with Google',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: cs.outline)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or with email',
                    style:
                        tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
              Expanded(child: Divider(color: cs.outline)),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Sign in')),
              ButtonSegment(value: true, label: Text('Create account')),
            ],
            selected: {_creating},
            showSelectedIcon: false,
            onSelectionChanged: busy ? null : (s) => _switchMode(s.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
              border: OutlineInputBorder(),
            ),
            validator: (v) => _emailPattern.hasMatch((v ?? '').trim())
                ? null
                : 'Enter a valid email address',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: !_showPassword,
            autofillHints: [
              _creating ? AutofillHints.newPassword : AutofillHints.password,
            ],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => busy ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: _creating ? 'At least 6 characters' : null,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                icon: Icon(_showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (v) => (v ?? '').length >= 6
                ? null
                : 'Password must be at least 6 characters',
          ),
          if (!_creating)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : _forgotPassword,
                child: const Text('Forgot password?'),
              ),
            )
          else
            const SizedBox(height: 12),
          if (account.error != null) ...[
            _Banner(
                text: account.error!,
                color: cs.error,
                icon: Icons.error_outline_rounded),
            const SizedBox(height: 12),
          ],
          if (_notice != null) ...[
            _Banner(
              text: _notice!,
              color: const Color(0xFF10B981),
              icon: Icons.mark_email_read_outlined,
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: busy ? null : _submit,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(_creating ? 'Create free account' : 'Sign in',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 24),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Accounts are free',
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Everything works offline without one. Upgrade to '
                  '${Entitlements.productName} any time for:',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                const _PerkList(compact: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple multicolour "G" so the Google button reads at a glance without
/// shipping Google's logo asset.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const SweepGradient(
        colors: [
          Color(0xFFEA4335),
          Color(0xFFFBBC05),
          Color(0xFF34A853),
          Color(0xFF4285F4),
          Color(0xFFEA4335),
        ],
      ).createShader(bounds),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, required this.icon});
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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
              'Accounts aren\'t available in this build. Everything on this '
              'device keeps working.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Signed in ─────────────────────────────────────────────

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.account});
  final AccountState account;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final email = account.email ?? '';
    final premium = account.isPremium;
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: cs.primary.withValues(alpha: 0.15),
          child: Text(
            email.isEmpty ? '?' : email.characters.first.toUpperCase(),
            style: tt.titleLarge
                ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: premium
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                      : cs.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  premium ? '⭐ Premium' : 'Free plan',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color:
                        premium ? const Color(0xFFB45309) : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Free plan: what Premium adds, and how to get it.
class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.account});
  final AccountState account;

  Future<void> _request(BuildContext context) async {
    final subject = Uri.encodeComponent('${Entitlements.productName} access');
    final body = Uri.encodeComponent(
      'Hi,\n\nI would like to activate ${Entitlements.productName}.\n\n'
      'My account email: ${account.email ?? ''}\n',
    );
    final uri = Uri.parse(
        'mailto:${Entitlements.supportEmail}?subject=$subject&body=$body');
    if (!await launchUrl(uri) && context.mounted) {
      await Clipboard.setData(ClipboardData(text: account.email ?? ''));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Email ${Entitlements.supportEmail}. Your account '
              'email is copied.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.12),
            const Color(0xFFA78BFA).withValues(alpha: 0.10),
          ],
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Upgrade to Premium',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Your free account works offline on this phone. Premium adds:',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const _PerkList(),
          const SizedBox(height: 8),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: () => _request(context),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Get Premium',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final entitled =
                  await AccountService.instance.refreshEntitlement();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(entitled
                    ? 'Premium is active. Sync is starting.'
                    : 'Not active yet. We usually activate within a few hours.'),
              ));
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Already paid? Check again'),
          ),
          const SizedBox(height: 8),
          Text(
            'We switch Premium on for your account (${account.email ?? ''}) '
            'after payment, usually within a few hours.',
            textAlign: TextAlign.center,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Premium: sync status and a manual sync.
class _SyncCard extends ConsumerWidget {
  const _SyncCard();

  static String _describe(SyncStatus status) {
    switch (status.stage) {
      case SyncStage.syncing:
        return 'Syncing…';
      case SyncStage.idle:
        final at = status.lastSyncedAt;
        if (at == null) return 'Backed up and in sync';
        return 'Last synced ${DateFormat('d MMM, HH:mm').format(at)}';
      case SyncStage.error:
        return status.message ?? 'Sync failed. It will retry automatically.';
      case SyncStage.inactive:
        return 'Premium is no longer active on this account';
      case SyncStage.signedOut:
        return 'Signed out';
      case SyncStage.unavailable:
        return 'Sync unavailable';
      case SyncStage.awaitingFirstSyncChoice:
        return 'Choose what to keep above to start syncing';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = ref.watch(syncStatusProvider).valueOrNull ??
        SyncService.instance.status;
    final isError = status.stage == SyncStage.error;
    final syncing = status.stage == SyncStage.syncing;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(isError ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                  color: isError ? cs.error : const Color(0xFF10B981)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Cloud backup and sync',
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _describe(status),
            style: tt.bodySmall
                ?.copyWith(color: isError ? cs.error : cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: syncing ? null : () => SyncService.instance.syncNow(),
            icon: syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 18),
            label: Text(syncing ? 'Syncing…' : 'Sync now'),
          ),
          const SizedBox(height: 12),
          const _PerkList(compact: true),
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.premium});
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        TextButton.icon(
          onPressed: () async {
            final ok = await ConfirmationDialog.show(
              context,
              title: 'Sign out?',
              message: premium
                  ? 'Sync stops on this device. Everything already here stays.'
                  : 'Everything on this device stays.',
              confirmLabel: 'Sign out',
            );
            if (ok) await AccountService.instance.signOut();
          },
          icon: Icon(Icons.logout_rounded, size: 18, color: cs.error),
          label: Text('Sign out', style: TextStyle(color: cs.error)),
        ),
        Text(
          'Signing out never deletes anything on this device.',
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Asked once, the first time an account signs in on a device that already
/// holds data.
///
/// Without it the first sync silently unions the two sets: someone who tried
/// the app out, made a few goals, then signed in would find their trial goals
/// sitting alongside the real ones with no way to tell which was which.
class _FirstSyncChoiceCard extends ConsumerWidget {
  const _FirstSyncChoiceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).valueOrNull ??
        SyncService.instance.status;
    if (status.stage != SyncStage.awaitingFirstSyncChoice) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.merge_type_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This device already has data',
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your account also has goals and habits saved. Choose what to '
              'keep before syncing starts.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => SyncService.instance
                    .resolveFirstSync(FirstSyncChoice.mergeBoth),
                child: const Text('Keep both'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmReplace(context),
                child: const Text('Use my account data instead'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Keeping both never loses anything, but anything you created '
              'twice will appear twice.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReplace(BuildContext context) async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Replace this device\'s data?',
      message: 'Everything currently on this device will be deleted and '
          'replaced with your account\'s data. This cannot be undone.',
      confirmLabel: 'Replace',
    );
    if (!confirmed) return;
    await SyncService.instance.resolveFirstSync(FirstSyncChoice.useAccountData);
  }
}
