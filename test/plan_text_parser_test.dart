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

  group('answers pasted from ChatGPT', () {
    test('markdown headings, Goal: line, chatter and Tips are handled', () {
      final r = PlanTextParser.parse('''Sure! Here's a 3-month plan to learn Python for data analysis:

## 🎯 Goal: Learn Python for Data Analysis in 3 Months

### **Month 1: Python Fundamentals**
- **Week 1–2:** Learn basic syntax, variables, and data types
- **Week 3:** Control flow (if statements, loops)

### **Month 2: Data Libraries**
1. **NumPy** – arrays and vectorized operations
2. **Pandas** – DataFrames, cleaning, grouping

---

**Tips:**
- Practice daily for 1 hour

Let me know if you'd like me to break this down further! 😊''');
      expect(r.goal.name, 'Learn Python for Data Analysis in 3 Months');
      expect(r.goal.emoji, '🎯');
      expect(titles(r), ['Month 1', 'Month 2']);
      expect(r.milestones[0].theme, 'Python Fundamentals');
      expect(tasks(r, 0).first, 'Week 1–2: Learn basic syntax, variables, and data types');
      expect(tasks(r, 1), [
        'NumPy – arrays and vectorized operations',
        'Pandas – DataFrames, cleaning, grouping',
      ]);
      final all = [for (final m in r.milestones) ...m.tasks.map((t) => t.text)];
      expect(all.any((t) => t.contains('Practice daily')), isFalse,
          reason: 'tips are not tasks');
      expect(all.any((t) => t.contains('Let me know')), isFalse,
          reason: 'sign-offs are dropped');
    });

    test('bold headings, goal from the intro, sub-points become notes', () {
      final r = PlanTextParser.parse('''Here's a structured plan for running your first marathon:

**Phase 1: Base Building (Weeks 1-4)**
* Run 3-4 times per week at an easy pace

**Phase 2: Endurance (Weeks 5-10)**
* Add a long run every weekend
  * Start at 10 miles
  * Increase by 1 mile each week
* Include one tempo run per week

Good luck with your training! 🏃''');
      expect(r.goal.name, 'Running your first marathon');
      expect(titles(r), ['Phase 1', 'Phase 2']);
      expect(tasks(r, 1),
          ['Add a long run every weekend', 'Include one tempo run per week']);
      expect(r.milestones[1].tasks[0].note,
          'Start at 10 miles\nIncrease by 1 mile each week');
    });

    test('a numbered step-by-step outline', () {
      final r = PlanTextParser.parse('''Absolutely! Here's a step-by-step plan to launch your online store:

1. **Research & Planning**
   - Identify your niche
   - Analyze competitors
2. **Set Up the Store**
   - Choose a platform (Shopify, WooCommerce)
3. **Launch**
   - Announce on social media

Would you like a marketing checklist too?''');
      expect(r.goal.name, 'Launch your online store');
      expect(titles(r), ['Research & Planning', 'Set Up the Store', 'Launch']);
      expect(tasks(r, 0), ['Identify your niche', 'Analyze competitors']);
    });

    test('a table: one milestone per row', () {
      final r = PlanTextParser.parse('''Here is a 2-week coding plan:

| Week | Focus | Tasks |
|------|-------|-------|
| 1 | Basics | Learn syntax, write hello world |
| 2 | Loops | Practice for loops; solve 5 problems |''');
      expect(r.goal.name, '2-week coding plan');
      expect(titles(r), ['Week 1', 'Week 2']);
      expect(r.milestones[0].theme, 'Basics');
      expect(tasks(r, 1), ['Practice for loops', 'Solve 5 problems']);
    });

    test('Focus: lines describe the milestone', () {
      final r = PlanTextParser.parse('''### Week 1
**Focus:** Getting started
- Install VS Code
### Week 2
**Focus:** Practice
- Solve 10 exercises''');
      expect(r.milestones[0].theme, 'Getting started');
      expect(tasks(r, 0), ['Install VS Code']);
    });

    test('a list of "Day N:" lines becomes one list of tasks', () {
      final r = PlanTextParser.parse('''Day 1: Learn greetings
Day 2: Numbers 1-20
Day 3: Practice with an app''');
      expect(titles(r), ['Plan']);
      expect(tasks(r, 0).first, 'Day 1: Learn greetings');
      expect(tasks(r, 0), hasLength(3));
    });

    test('the format our ChatGPT prompt asks for', () {
      final r = PlanTextParser.parse('''Goal: Get fit for summer
Lose 5 kg and build a running habit.

Milestone 1: Build the habit
- Walk 30 minutes daily
- Sleep 8 hours (high)
Milestone 2: Start running
- Run 3x per week''');
      expect(r.goal.name, 'Get fit for summer');
      expect(r.goal.description, 'Lose 5 kg and build a running habit.');
      expect(titles(r), ['Build the habit', 'Start running']);
      expect(r.milestones[0].tasks[1].priority, 1);
    });

    test('JSON in the app\'s plan format, even inside a code fence', () {
      final r = PlanTextParser.parse('''```json
{"goal":{"name":"Read 12 books","description":"","emoji":"📚","color_hex":"#34D399","duration_label":"1 Year"},
 "milestones":[{"title":"Q1","theme":"Start","order":1,"tasks":[{"text":"Pick 3 books","priority":0,"order":1}]}]}
```''');
      expect(r.goal.name, 'Read 12 books');
      expect(r.goal.emoji, '📚');
      expect(tasks(r, 0), ['Pick 3 books']);
    });
  });

  test('the ChatGPT prompt carries the goal and the format we parse', () {
    final p = PlanTextParser.chatGptPrompt('  Run a half marathon ');
    expect(p, contains('Run a half marathon'));
    expect(p, contains('Goal: <short goal name>'));
    expect(p, contains('Milestone 1:'));
    expect(p, contains('no introduction'));
  });
}
