import '../../shared/widgets/walkthrough.dart';

/// The guided tour for each flow, in one place so the copy stays
/// consistent. Each one plays once, the first time its screen opens, and
/// again after "Replay app tour" on the Me tab.
///
/// Steps point at [WalkTarget] ids. A step whose target isn't on screen
/// (no habits yet, no schedule today) is skipped automatically.
abstract final class Tours {
  static const today = 'today';
  static const goals = 'goals';
  static const goalDetail = 'goal_detail';
  static const habits = 'habits';
  static const pet = 'pet';
  static const me = 'me';
  static const focus = 'focus';

  static const todaySteps = [
    WalkStep(
      emoji: '👋',
      title: 'Welcome to RoadmapX',
      body: 'Here\'s a quick tour. Today is your home: everything due now, '
          'in the order you live your day.',
    ),
    WalkStep(
      target: 'today.companion',
      emoji: '💍',
      title: 'Your perfect-day ring',
      body: 'Finish today\'s habits and tasks to close the ring. Everything '
          'you do earns XP, levels you up and gives coins for your pet.',
    ),
    WalkStep(
      target: 'today.focus',
      emoji: '⏱️',
      title: 'Focus timer',
      body: 'Start a focus session on any task. Every focused minute earns XP.',
    ),
    WalkStep(
      target: 'today.habits',
      emoji: '✅',
      title: 'Today\'s habits',
      body: 'Tap a habit to tick it off. Long-press any item for its options.',
    ),
    WalkStep(
      target: 'today.tasks',
      emoji: '📝',
      title: 'Tasks due today',
      body: 'Tap the circle to complete a task. Swipe left to edit or delete, '
          'and long-press for more, like moving it to a goal.',
    ),
    WalkStep(
      target: 'today.fab',
      emoji: '➕',
      title: 'Add anything',
      body: 'One button for everything: a quick task, a goal, a habit, a '
          'routine, or a whole plan pasted from text.',
    ),
    WalkStep(
      target: 'shell.nav',
      emoji: '🧭',
      title: 'Find your way around',
      body: 'Goals hold your long-term plans, Habits your routines, Pet your '
          'companion, and Me your account and settings. Each one has a short '
          'tour the first time you open it.',
    ),
  ];

  static const goalsSteps = [
    WalkStep(
      emoji: '🎯',
      title: 'Your goals',
      body: 'Big plans live here, broken into milestones and tasks so you '
          'always know the next step.',
    ),
    WalkStep(
      target: 'goals.filters',
      emoji: '🔎',
      title: 'Filter',
      body: 'Switch between active goals, the ones you\'re focusing on, all, '
          'and archived.',
    ),
    WalkStep(
      target: 'goals.card',
      emoji: '📈',
      title: 'Goal cards',
      body: 'Tap to open a goal. The line under it says if you\'re on pace '
          'for the target date. Long-press for options, or drag the handle '
          'to reorder.',
    ),
    WalkStep(
      target: 'goals.fab',
      emoji: '✨',
      title: 'Create a goal',
      body: 'Have AI build the plan, paste one from ChatGPT or your notes, '
          'start from a template, or set it up yourself.',
    ),
  ];

  static const goalDetailSteps = [
    WalkStep(
      target: 'goal.header',
      emoji: '🗺️',
      title: 'Your goal at a glance',
      body: 'Overall progress and the target date. The buttons up top open '
          'focus mode and editing.',
    ),
    WalkStep(
      target: 'goal.pace',
      emoji: '🏁',
      title: 'Are you on pace?',
      body: 'Time used against work done, and what it takes to finish on time.',
    ),
    WalkStep(
      target: 'goal.addMilestone',
      emoji: '🪜',
      title: 'Milestones',
      body: 'Break the goal into stages. Each milestone holds its own tasks.',
    ),
    WalkStep(
      target: 'goal.milestone',
      emoji: '👆',
      title: 'Work through it',
      body: 'Tap a milestone to see its tasks and add more. Swipe left to '
          'edit or delete, long-press for options, drag the handle to reorder.',
    ),
  ];

  static const habitsSteps = [
    WalkStep(
      emoji: '🔁',
      title: 'Build habits',
      body: 'Small daily routines, grouped by time of day.',
    ),
    WalkStep(
      target: 'habits.week',
      emoji: '📅',
      title: 'Pick a day',
      body: 'See any day this week. Ticks are saved for the day you pick.',
    ),
    WalkStep(
      target: 'habits.tabs',
      emoji: '📊',
      title: 'Filter and analytics',
      body: 'Show what\'s left or what\'s done. Analytics has streaks and a '
          'month calendar for every habit.',
    ),
    WalkStep(
      target: 'habits.list',
      emoji: '✅',
      title: 'Tick them off',
      body: 'Tap a habit to mark it done. Long-press or swipe left to edit, '
          'set reminders or delete.',
    ),
    WalkStep(
      target: 'habits.fab',
      emoji: '➕',
      title: 'New habit',
      body: 'Choose an icon, colour, days of the week and a reminder time.',
    ),
  ];

  static const petSteps = [
    WalkStep(
      target: 'pet.room',
      emoji: '🐾',
      title: 'Meet your companion',
      body: 'Your pet grows happier as you get things done. Tap it to say hi.',
    ),
    WalkStep(
      target: 'pet.needs',
      emoji: '🍖',
      title: 'Keep it cared for',
      body: 'Food, water, fun and cleanliness drop over time. Use items from '
          'the store to keep the bars up.',
    ),
    WalkStep(
      target: 'pet.coins',
      emoji: '🪙',
      title: 'Coins',
      body: 'You earn coins from XP: finishing habits, tasks, perfect days '
          'and focus minutes.',
    ),
    WalkStep(
      target: 'pet.store',
      emoji: '🛒',
      title: 'The store',
      body: 'Spend coins on food, drinks and toys, then tap an item to give '
          'it to your pet.',
    ),
  ];

  static const meSteps = [
    WalkStep(
      target: 'me.profile',
      emoji: '🙂',
      title: 'Your profile',
      body: 'Your level, streak and name. Tap to change what we call you.',
    ),
    WalkStep(
      target: 'me.plan',
      emoji: '☁️',
      title: 'Account and Premium',
      body: 'Sign in for free to keep your plan safe. Premium adds sync '
          'across devices, cloud backup and the AI coach.',
    ),
    WalkStep(
      target: 'me.tools',
      emoji: '📊',
      title: 'Insights and schedule',
      body: 'See your progress over time and set up weekly time blocks.',
    ),
    WalkStep(
      target: 'me.app',
      emoji: '⚙️',
      title: 'Settings',
      body: 'Notifications, appearance, AI coach and backups. You can '
          'replay this tour from here any time.',
    ),
  ];

  static const focusSteps = [
    WalkStep(
      target: 'focus.ring',
      emoji: '⏱️',
      title: 'Focus timer',
      body: 'Work in focused blocks. Your pet keeps you company.',
    ),
    WalkStep(
      target: 'focus.task',
      emoji: '📝',
      title: 'Focus on a task',
      body: 'Optionally pick a task. When time\'s up you can mark it done.',
    ),
    WalkStep(
      target: 'focus.start',
      emoji: '▶️',
      title: 'Pick a length and start',
      body: 'Every focused minute earns XP and coins. End early and the '
          'minutes you did still count (5 minutes or more).',
    ),
  ];
}
