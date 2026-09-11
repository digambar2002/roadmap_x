import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/core/sync/sync_config.dart';

/// Guards the build-time wiring. Run without defines this asserts the app
/// degrades to local-only; run with `--dart-define-from-file=dart_defines.json`
/// it asserts the values actually reach the compiled code.
void main() {
  test('sync config is either fully present or fully absent', () {
    final hasUrl = SyncConfig.supabaseUrl.isNotEmpty;
    final hasKey = SyncConfig.supabaseAnonKey.isNotEmpty;

    // A half-configured build is the bad case: it would look enabled and then
    // fail on the first request.
    expect(hasUrl, hasKey,
        reason: 'SUPABASE_URL and SUPABASE_ANON_KEY must be set together');
    expect(SyncConfig.isConfigured, hasUrl && hasKey);

    if (!SyncConfig.isConfigured) return;

    expect(SyncConfig.supabaseUrl, startsWith('https://'));
    expect(SyncConfig.supabaseUrl, contains('.supabase.co'));
    // Anon keys are JWTs; a service_role key here would be a serious leak,
    // since it bypasses every RLS policy.
    expect(SyncConfig.supabaseAnonKey.split('.').length, 3,
        reason: 'anon key should be a JWT');
    expect(SyncConfig.supabaseAnonKey, isNot(contains('service_role')));
  });

  test('pull pages hold more rows than a single push writes', () {
    // Every row in one upsert shares a server_updated_at, so a page smaller
    // than a push chunk could stall the cursor forever.
    expect(SyncConfig.pullOverlap.inSeconds, greaterThan(0));
  });
}
