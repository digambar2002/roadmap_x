/// Supabase connection details, supplied at build time.
///
/// Passed with `--dart-define` rather than checked in, so the repository stays
/// free of project-specific values and a fork can point at its own backend:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
///
/// The anon key is safe to ship — it grants nothing on its own. Row Level
/// Security is what actually protects the data; see `supabase/schema.sql`.
///
/// When the defines are absent the app runs exactly as before: fully local,
/// with sync reported as unavailable rather than broken.
class SyncConfig {
  const SyncConfig._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Server table holding every synced row across all collections.
  static const String recordsTable = 'records';

  /// Server table holding the manually flipped premium flag.
  static const String profilesTable = 'profiles';

  /// How long to coalesce local edits before pushing. Long enough that typing
  /// a task title is one request, short enough to feel immediate.
  static const Duration pushDebounce = Duration(seconds: 2);

  /// How long to coalesce inbound realtime events before pulling.
  static const Duration pullDebounce = Duration(milliseconds: 400);

  /// Overlap subtracted from the pull cursor on each request.
  ///
  /// Two rows committed in the same instant can land either side of a cursor
  /// taken from the newest one, so the next pull re-reads a short window.
  /// Merging is idempotent, making the duplicate work harmless and the gap
  /// impossible.
  static const Duration pullOverlap = Duration(seconds: 2);
}
