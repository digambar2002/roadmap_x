import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/services/onboarding.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../../core/subscription/entitlements.dart';
import '../../premium/providers/premium_provider.dart';

/// Shown once, before the app has any data.
///
/// The choice is deliberately about *data*, not about accounts: starting fresh
/// and signing in produce very different results on a device that already has
/// goals, and the only moment that question is cheap to answer is before any
/// exist.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _startFresh(BuildContext context, WidgetRef ref) async {
    await Onboarding.markComplete(ref.read(sharedPreferencesProvider));
    if (!context.mounted) return;
    context.go('/dashboard');
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    await Onboarding.markComplete(ref.read(sharedPreferencesProvider));
    if (!context.mounted) return;
    // Straight to the account screen: signing in here, before anything local
    // exists, means the account's data arrives cleanly with nothing to merge.
    context.go('/dashboard');
    context.push('/premium');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final syncAvailable = ref.watch(syncAvailableProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: AdaptivePage(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: context.pageGutter,
                vertical: 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        width: 108,
                        height: 108,
                        // The icon is a build asset; if it is ever missing the
                        // welcome screen should still be usable.
                        errorBuilder: (_, __, ___) =>
                            const Text('🧭', style: TextStyle(fontSize: 64)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to RoadmapX',
                    textAlign: TextAlign.center,
                    style: tt.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Plan goals, break them into milestones, and keep the '
                    'habits that get you there.',
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () => _startFresh(context, ref),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Start fresh'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Everything stays on this device. No account needed.',
                    textAlign: TextAlign.center,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (syncAvailable) ...[
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => _signIn(context, ref),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('I already have an account'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in first and your existing goals and habits come '
                      'down to this device.',
                      textAlign: TextAlign.center,
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    '${Entitlements.productName} adds sync across your '
                    'devices. You can sign in any time from Settings.',
                    textAlign: TextAlign.center,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
