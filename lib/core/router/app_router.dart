import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/onboarding.dart';
import '../services/shared_preferences_provider.dart';
import '../router/app_shell.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/today/presentation/today_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../features/schedule/presentation/schedule_screen.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';
import '../../features/habits/presentation/habits_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/premium/presentation/premium_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/me/presentation/me_screen.dart';
import '../../features/pet/presentation/pet_screen.dart';
import '../../features/focus/presentation/focus_timer_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);

  return GoRouter(
    initialLocation: '/today',
    redirect: (context, state) {
      if (!Onboarding.isComplete(prefs)) {
        const allowed = {'/welcome', '/premium'};
        if (allowed.contains(state.matchedLocation)) return null;
        return '/welcome';
      }
      final uri = state.uri;
      if (uri.scheme == 'com.naviwix.roadmapx') {
        // OAuth callback: Supabase has already consumed the tokens, so just
        // return to the account screen where sign-in was started.
        return '/premium';
      }
      if (uri.scheme == 'roadmapx') {
        // Home-screen widget deep links: roadmapx://roadmapx/<screen>.
        if (uri.path.contains('settings')) return '/settings';
        if (uri.path.contains('add')) return '/today?capture=1';
        return '/today';
      }
      // Normalise other "today" links, but leave /today itself (and its
      // query, e.g. ?capture=1) alone.
      if (uri.path != '/today' &&
          (uri.host == 'today' || uri.path.contains('today'))) {
        return '/today';
      }
      if (state.matchedLocation == '/' || uri.path == '/' || uri.path.isEmpty) {
        return '/today';
      }
      return null;
    },
    errorBuilder: (context, state) => const TodayScreen(),
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/today',
      ),
      // The old home route; kept so saved links and notifications still land.
      GoRoute(
        path: '/dashboard',
        redirect: (_, __) => '/today',
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/goals',
                builder: (context, state) => const GoalsScreen(),
                routes: [
                  GoRoute(
                    path: ':goalId',
                    // tryParse: a malformed deep link ("/goals/abc") must
                    // not crash the route build. id 0 never matches a
                    // goal, so the detail screen pops back gracefully.
                    builder: (context, state) => GoalDetailScreen(
                      goalId:
                          int.tryParse(state.pathParameters['goalId']!) ?? 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/habits',
                builder: (context, state) => const HabitsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/pet',
                builder: (context, state) => const PetScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/me',
                builder: (context, state) => const MeScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full task planner: overdue, today, this week and later.
      GoRoute(
        path: '/tasks',
        builder: (context, state) => const TodayScreen(),
      ),
      GoRoute(
        path: '/analytics',
        builder: (context, state) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: '/schedule',
        builder: (context, state) => const ScheduleScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: '/premium',
        builder: (context, state) => const PremiumScreen(),
      ),
      GoRoute(
        path: '/focus-timer',
        builder: (context, state) => FocusTimerScreen(
          taskId: int.tryParse(state.uri.queryParameters['task'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/focus/:goalId',
        builder: (context, state) => FocusScreen(
          goalId: int.tryParse(state.pathParameters['goalId']!) ?? 0,
        ),
      ),
    ],
  );
});
