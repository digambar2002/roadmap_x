import '../../features/goals/data/goal_repository.dart';
import '../../features/milestones/data/milestone_repository.dart';
import '../../features/tasks/data/task_repository.dart';

class GoalTemplate {
  final String name;
  final String description;
  final String emoji;
  final List<MilestoneTemplate> milestones;

  const GoalTemplate({
    required this.name,
    required this.description,
    required this.emoji,
    required this.milestones,
  });
}

class MilestoneTemplate {
  final String title;
  final String theme;
  final List<String> tasks;

  const MilestoneTemplate({
    required this.title,
    required this.theme,
    required this.tasks,
  });
}

class GoalTemplateService {
  GoalTemplateService._();
  static final GoalTemplateService instance = GoalTemplateService._();

  List<GoalTemplate> get templates => const [
        GoalTemplate(
          name: 'Master Flutter Development',
          description: 'Build production-ready Flutter apps from scratch',
          emoji: '📱',
          milestones: [
            MilestoneTemplate(
              title: 'Dart fundamentals',
              theme: 'Foundation',
              tasks: [
                'Complete Dart syntax refresher',
                'Practice async/await patterns',
                'Build 3 small CLI utilities',
              ],
            ),
            MilestoneTemplate(
              title: 'Flutter UI mastery',
              theme: 'Interface',
              tasks: [
                'Rebuild a login screen with custom widgets',
                'Implement responsive layouts',
                'Add animations to 2 screens',
              ],
            ),
            MilestoneTemplate(
              title: 'Ship a Flutter app',
              theme: 'Launch',
              tasks: [
                'Set up state management',
                'Integrate local database',
                'Publish to Play Store / TestFlight',
              ],
            ),
          ],
        ),
        GoalTemplate(
          name: 'Crack DSA Interviews',
          description: 'Structured prep for coding interviews',
          emoji: '🧮',
          milestones: [
            MilestoneTemplate(
              title: 'Core patterns',
              theme: 'Patterns',
              tasks: [
                'Two pointers — 10 problems',
                'Sliding window — 10 problems',
                'Binary search — 10 problems',
              ],
            ),
            MilestoneTemplate(
              title: 'Trees & graphs',
              theme: 'Advanced',
              tasks: [
                'BFS/DFS — 15 problems',
                'Tree traversals — 10 problems',
                'Shortest path — 8 problems',
              ],
            ),
            MilestoneTemplate(
              title: 'Mock interviews',
              theme: 'Practice',
              tasks: [
                'Complete 5 timed mock sessions',
                'Review weak topics list',
                'Do 2 full-length interview simulations',
              ],
            ),
          ],
        ),
        GoalTemplate(
          name: 'Get Fit in 90 Days',
          description: 'Build a sustainable fitness habit',
          emoji: '💪',
          milestones: [
            MilestoneTemplate(
              title: 'Foundation (Weeks 1–4)',
              theme: 'Start',
              tasks: [
                'Walk 30 min daily',
                'Strength train 3x/week',
                'Track calories for 2 weeks',
              ],
            ),
            MilestoneTemplate(
              title: 'Progress (Weeks 5–8)',
              theme: 'Build',
              tasks: [
                'Increase weights by 10%',
                'Add 1 cardio session/week',
                'Meal prep 4 days/week',
              ],
            ),
            MilestoneTemplate(
              title: 'Peak (Weeks 9–12)',
              theme: 'Finish',
              tasks: [
                'Hit target body measurements',
                'Run 5K without stopping',
                'Create maintenance plan',
              ],
            ),
          ],
        ),
        GoalTemplate(
          name: 'Launch a SaaS MVP',
          description: 'Validate and ship a micro-SaaS product',
          emoji: '🚀',
          milestones: [
            MilestoneTemplate(
              title: 'Validate idea',
              theme: 'Discovery',
              tasks: [
                'Interview 10 potential users',
                'Define core problem statement',
                'Sketch landing page copy',
              ],
            ),
            MilestoneTemplate(
              title: 'Build MVP',
              theme: 'Build',
              tasks: [
                'Implement auth + core workflow',
                'Set up billing (Stripe/Razorpay)',
                'Deploy staging environment',
              ],
            ),
            MilestoneTemplate(
              title: 'Launch & iterate',
              theme: 'Growth',
              tasks: [
                'Launch on Product Hunt / communities',
                'Collect first 10 user feedback calls',
                'Ship top 3 requested improvements',
              ],
            ),
          ],
        ),
        GoalTemplate(
          name: 'Read 24 Books This Year',
          description: 'Consistent reading habit with depth',
          emoji: '📚',
          milestones: [
            MilestoneTemplate(
              title: 'Habit setup',
              theme: 'Routine',
              tasks: [
                'Read 20 pages daily for 21 days',
                'Pick first 6 books',
                'Create reading tracker',
              ],
            ),
            MilestoneTemplate(
              title: 'Quarterly sprint',
              theme: 'Volume',
              tasks: [
                'Finish 6 books this quarter',
                'Write 1-page summary per book',
                'Share 3 key takeaways weekly',
              ],
            ),
            MilestoneTemplate(
              title: 'Deep reading',
              theme: 'Retention',
              tasks: [
                'Re-read highlights monthly',
                'Apply 1 idea per book to life/work',
                'Hit 24 books by year end',
              ],
            ),
          ],
        ),
      ];

  Future<int> createFromTemplate({
    required GoalTemplate template,
    required int colorHex,
    required DateTime targetDate,
  }) async {
    final goal = await GoalRepository.instance.create(
      name: template.name,
      description: template.description,
      emoji: template.emoji,
      colorHex: colorHex,
      targetDate: targetDate,
    );

    for (final msTpl in template.milestones) {
      final ms = await MilestoneRepository.instance.create(
        goalId: goal.id,
        title: msTpl.title,
        theme: msTpl.theme,
      );
      for (final taskText in msTpl.tasks) {
        await TaskRepository.instance.create(
          milestoneId: ms.id,
          text: taskText,
        );
      }
    }
    return goal.id;
  }
}
