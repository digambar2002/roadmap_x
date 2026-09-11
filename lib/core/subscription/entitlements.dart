/// What the free tier includes, and what activation unlocks.
///
/// The free tier is the whole app running locally: goals, milestones, tasks,
/// schedule, streaks, analytics, and file backup/restore. Paid adds the things
/// that either cost money to run or only make sense across devices.
class Entitlements {
  const Entitlements._();

  /// Active (non-archived) goals allowed without activation. Archiving frees a
  /// slot, and nothing is ever deleted or hidden when a subscription lapses —
  /// existing goals stay readable and editable, only creating new ones stops.
  static const int freeActiveGoalLimit = 3;

  /// Where users are told to write to ask for activation. Change this to
  /// whichever address you actually watch.
  static const String supportEmail = 'digambar.chaudhari@networcx.io';

  static const String productName = 'RoadmapX Premium';

  static const List<String> perks = [
    'Realtime sync across all your devices',
    'Cloud backup — restore onto a new phone in seconds',
    'AI coach: daily briefings, weekly reviews, and plan adjustments',
    'Unlimited goals',
  ];
}
