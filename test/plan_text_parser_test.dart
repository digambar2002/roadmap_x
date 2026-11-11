import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/features/ai_goal/data/plan_text_parser.dart';

void main() {
  List<String> titles(r) => [for (final m in r.milestones) m.title as String];
  List<String> tasks(r, int i) =>
      [for (final t in r.milestones[i].tasks) t.text as String];

  test('goal, description, week sections and tasks', () {
    final r = PlanTextParser.parse('''
Learn Spanish
Get conversational by summer.

Week 1: Basics
  - Learn 100 common words
  - Practise greetings !
## Week 2
1. Past tense
- [ ] Watch a film in Spanish
''');
    expect(r.goal.name, 'Learn Spanish');
    expect(r.goal.description, 'Get conversational by summer.');
    expect(titles(r), ['Week 1', 'Week 2']);
    expect(r.milestones[0].theme, 'Basics');
    expect(tasks(r, 0), ['Learn 100 common words', 'Practise greetings']);
    expect(r.milestones[0].tasks[1].priority, 1);
    expect(tasks(r, 1), ['Past tense', 'Watch a film in Spanish']);
    expect(r.goal.durationLabel, '2 Weeks');
  });

  test('a bare list becomes one milestone of tasks', () {
    final r = PlanTextParser.parse('''
- Book flights
- Renew passport (urgent)
- Pack bags
''');
    expect(r.goal.name, 'Imported plan');
    expect(titles(r), ['Tasks']);
    expect(tasks(r, 0), ['Book flights', 'Renew passport', 'Pack bags']);
    expect(r.milestones[0].tasks[1].priority, 2);
  });

  test('bullets with indented children are sections', () {
    final r = PlanTextParser.parse('''
# Launch the app
- Design
  - Wireframes
  - Visual design
- Build
  - API
  - Mobile client
''');
    expect(r.goal.name, 'Launch the app');
    expect(titles(r), ['Design', 'Build']);
    expect(tasks(r, 1), ['API', 'Mobile client']);
  });

  test('colon lines and shouted lines start sections', () {
    final r = PlanTextParser.parse('''
Marathon training
RESEARCH
- Pick a race
Training:
- Run 3x a week
- Long run on Sundays
''');
    expect(titles(r), ['RESEARCH', 'Training']);
    expect(tasks(r, 1), ['Run 3x a week', 'Long run on Sundays']);
  });

  test('a leading emoji becomes the goal emoji', () {
    final r = PlanTextParser.parse('🏃 Run a 10k\n- Buy shoes');
    expect(r.goal.emoji, '🏃');
    expect(r.goal.name, 'Run a 10k');
  });

  test('markdown checkboxes, numbering and bold are cleaned up', () {
    final r = PlanTextParser.parse('''
Home project
Phase 1 - Planning
1) **Measure rooms**
2) [x] Get quotes
''');
    expect(titles(r), ['Phase 1']);
    expect(r.milestones[0].theme, 'Planning');
    expect(tasks(r, 0), ['Measure rooms', 'Get quotes']);
  });

  test('empty or junk text gives no milestones', () {
    expect(PlanTextParser.parse('   \n  ').milestones, isEmpty);
    expect(PlanTextParser.parse('Just a title').milestones, isEmpty);
  });
}
