import 'dart:convert';

import '../../../core/ai/gemini_service.dart';

/// Turns pasted text into a goal plan without any network call.
///
/// Written above all for answers copied out of ChatGPT and similar
/// assistants, which wrap a plan in a recognisable shape:
///
/// ```text
/// Sure! Here's a 3-month plan to learn Python:   ← chatter: skipped, but
///                                                   "learn Python" is kept
///                                                   as the goal if no other
/// ## 🎯 Goal: Learn Python for Data Analysis      ← "Goal:" line: the goal
/// ### **Month 1: Fundamentals**                   ← headings, **bold lines**,
/// - **Week 1–2:** Syntax and data types             "Week 1:", "Phase 2 –"
///   - Variables, strings, lists                   ← sub-points: task notes
/// 1. **NumPy** – arrays                           ← bullets/numbers: tasks
/// | Week | Focus | Tasks |                        ← tables: one milestone
/// **Tips:** …                                       per row
/// Let me know if you'd like more detail! 😊       ← tips and sign-offs: dropped
/// ```
///
/// It also accepts the app's own JSON plan format, and plain notes: the first
/// line is the goal, bullets are tasks, and "Day 1: …" lines become a list.
class PlanTextParser {
  const PlanTextParser._();

  /// A prompt for ChatGPT (or any assistant) that asks for exactly the
  /// format this parser reads best.
  static String chatGptPrompt(String goal) => '''
Create a step-by-step plan for this goal: ${goal.trim()}

Reply in exactly this format, with no introduction or closing remarks:

Goal: <short goal name>
<one sentence describing the outcome>

Milestone 1: <milestone name>
- <concrete task starting with a verb>
- <concrete task starting with a verb> (high)

Milestone 2: <milestone name>
- <concrete task>

Rules: 3 to 5 milestones in order, 4 to 8 concrete tasks in each, one task
per line, and add (high) after the most important tasks.''';

  static final _mdHeading = RegExp(r'^(#{1,6})\s+(.+?)\s*#*$');
  static final _boldLine = RegExp(r'^(?:\*\*|__)(.+?)(?:\*\*|__)\s*:?\s*$');
  static final _bullet = RegExp(
    r'^(?:[-*•◦▪‣–—+>]|\d{1,3}[.)]|[a-zA-Z][.)]|\(\d{1,3}\))\s+(.+)$',
  );
  static final _checkbox = RegExp(r'^(?:\[[ xX✓✔]?\]|☐|☑️?|✅|✔️?)\s*');
  static final _rule = RegExp(r'^([-*_=]\s*){3,}$');
  static final _sectionWord = RegExp(
    r'^(week|month|phase|day|step|stage|part|milestone|sprint|level|module|'
    r'chapter|section|quarter|q[1-4]|term|unit|round|block|session|lesson)'
    r'\b\s*[\d\-–—&+ ]*',
    caseSensitive: false,
  );
  static final _genericTitle = RegExp(
    r'^(milestone|step|part|section|stage|module|chapter|unit|level|round|'
    r'block|lesson)\s*\d+[a-z]?$',
    caseSensitive: false,
  );
  static final _goalLabel = RegExp(
    r'^(?:goal|objective|target|aim|your goal|main goal)\s*[:\-–—]\s*(.+)$',
    caseSensitive: false,
  );
  static final _intro = RegExp(
    r"^(sure|certainly|absolutely|of course|great|okay|ok|alright|yes|"
    r"here['’]s|here is|here are|below is|below are|i['’]ve|i have|"
    r"i['’]d|happy to|glad to|awesome|perfect|excellent)\b",
    caseSensitive: false,
  );
  static final _outro = RegExp(
    r"^(let me know|good luck|hope this|i hope|feel free|you['’]ve got this|"
    r"would you like|do you want|if you['’]d like|if you want|happy learning|"
    r"best of luck|enjoy|cheers|stay consistent|remember,|you can do it|"
    r"want me to|shall i|should i)\b",
    caseSensitive: false,
  );
  static final _planOf = RegExp(
    r'\b(?:plan|roadmap|schedule|guide|strategy|program|programme|outline|'
    r'breakdown|checklist|routine|path)\s+(?:for|to|on|of)\s+(.+?)\s*[:.!]*$',
    caseSensitive: false,
  );

  /// "Here is a 2-week coding plan:" → "2-week coding plan".
  static final _hereIs = RegExp(
    r"^(?:sure[!,.]?\s*)?(?:here['’]s|here is|below is)\s+(?:a|an|your|the)\s+"
    r'(.{4,60}?)\s*[:.!]*$',
    caseSensitive: false,
  );
  static const _skipSections = {
    'tips',
    'tip',
    'pro tips',
    'pro tip',
    'notes',
    'note',
    'summary',
    'conclusion',
    'final thoughts',
    'key takeaways',
    'takeaways',
    'resources',
    'helpful resources',
    'recommended resources',
    'tools',
    'why this works',
    'additional tips',
    'bonus tips',
    'general tips',
    'important notes',
    'disclaimer',
    'motivation',
    'tracking progress',
    'final tips',
    'extra tips',
    'quick tips',
    'reminders',
  };
  static final _leadingEmoji = RegExp(
    r'^((?:[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F000}-\u{1F2FF}\u{2B00}-'
    r'\u{2BFF}][\u{FE0F}\u{200D}\u{20E3}]?)+)\s*',
    unicode: true,
  );

  static AiGoalResponse parse(String raw) {
    final json = _tryJson(raw);
    if (json != null) return json;

    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\t', '    ')
        .split('\n');

    final b = _Builder();

    // Headings: the single top-level one (when deeper ones exist) is the goal.
    final levels = [
      for (final l in lines)
        if (_mdHeading.firstMatch(l.trim()) case final m?) m.group(1)!.length,
    ];
    final minLevel =
        levels.isEmpty ? 0 : levels.reduce((a, c) => a < c ? a : c);
    final topCount = levels.where((l) => l == minLevel).length;
    final hasDeeper = levels.any((l) => l > minLevel);

    var inFence = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final t = line.trim();
      if (t.startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (t.isEmpty || inFence || _rule.hasMatch(t)) continue;

      // ── Tables ──────────────────────────────────────────
      if (t.startsWith('|')) {
        final rows = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.add(lines[i].trim());
          i++;
        }
        i--;
        _table(rows, b);
        continue;
      }

      // ── Chatter ─────────────────────────────────────────
      final plain = _clean(t);
      if (_intro.hasMatch(plain) || _outro.hasMatch(plain)) {
        if (b.goalName == null && b.introGoal == null) {
          final m = _planOf.firstMatch(plain) ?? _hereIs.firstMatch(plain);
          if (m != null) {
            b.introGoal = _capitalise(_clean(m.group(1)!));
          }
        }
        continue;
      }

      final indent = line.length - line.trimLeft().length;

      // ── Headings: markdown or a whole line in bold ──────
      final md = _mdHeading.firstMatch(t);
      final bold = md == null ? _boldLine.firstMatch(t) : null;
      if (md != null || bold != null) {
        final text = _clean((md ?? bold)!.group(md != null ? 2 : 1)!);
        final level = md?.group(1)!.length ?? 99;
        final isTop = md != null &&
            level == minLevel &&
            topCount == 1 &&
            (hasDeeper || level == 1);
        b.heading(text, maybeGoal: isTop);
        continue;
      }

      // ── Bullets, numbers, checkboxes ────────────────────
      final bm = _bullet.firstMatch(t);
      if (bm != null || _checkbox.hasMatch(t)) {
        final text =
            _clean((bm != null ? bm.group(1)! : t).replaceFirst(_checkbox, ''));
        if (text.isEmpty) continue;
        final next = _nextNonEmpty(lines, i);
        final hasChildren = next != null &&
            _indentOf(next) > indent &&
            (_bullet.hasMatch(next.trim()) || _checkbox.hasMatch(next.trim()));
        b.bullet(text, indent: indent, hasChildren: hasChildren);
        continue;
      }

      // ── Plain lines ─────────────────────────────────────
      b.plain(plain);
    }

    return b.build();
  }

  // ── Tables ───────────────────────────────────────────────

  static void _table(List<String> rows, _Builder b) {
    List<String> cells(String row) {
      var r = row.trim();
      if (r.startsWith('|')) r = r.substring(1);
      if (r.endsWith('|')) r = r.substring(0, r.length - 1);
      return r.split('|').map((c) => _clean(c)).toList();
    }

    final data = [
      for (final r in rows)
        if (!RegExp(r'^[\s|:\-]+$').hasMatch(r)) cells(r),
    ];
    if (data.length < 2) return;
    final header = data.first.map((h) => h.toLowerCase()).toList();
    int find(List<String> words, {Set<int> not = const {}}) {
      for (var c = 0; c < header.length; c++) {
        if (not.contains(c)) continue;
        if (words.any((w) => header[c].contains(w))) return c;
      }
      return -1;
    }

    var tasksCol = find([
      'task',
      'activit',
      'action',
      'to-do',
      'todo',
      'steps',
      'what to do',
      'exercise',
      'deliverable',
      'practice',
      'work'
    ]);
    if (tasksCol <= 0) tasksCol = header.length - 1;
    final themeCol = find([
      'focus',
      'theme',
      'topic',
      'goal',
      'area',
      'subject',
      'skill',
      'objective'
    ], not: {
      0,
      tasksCol
    });
    final firstHeader = data.first.first;
    final timeHeader = _sectionWord.hasMatch(firstHeader);

    for (final row in data.skip(1)) {
      if (row.isEmpty || row.every((c) => c.isEmpty)) continue;
      final first = row.first;
      final title = timeHeader && RegExp(r'^[\d\-–— ]+$').hasMatch(first)
          ? '${_capitalise(firstHeader)} $first'
          : first;
      final theme = themeCol >= 0 && themeCol < row.length ? row[themeCol] : '';
      final tasksCell = tasksCol < row.length ? row[tasksCol] : '';
      b.startSection(title.isEmpty ? 'Milestone' : title, theme: theme);
      for (final task in _splitList(tasksCell)) {
        b.section!.addTask(task);
      }
    }
  }

  /// "a; b • c" → [a, b, c]. Commas split only when every part is a phrase,
  /// so "Read chapters 1, 2, 3" stays whole.
  static List<String> _splitList(String cell) {
    final parts = cell
        .split(
            RegExp(r'\s*(?:;|•|<br\s*/?>|\s+\+\s+)\s*', caseSensitive: false))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.length == 1 && parts.first.contains(', ')) {
      final byComma = parts.first.split(RegExp(r',\s+'));
      if (byComma.every((p) => p.trim().split(RegExp(r'\s+')).length >= 2)) {
        return byComma;
      }
    }
    return parts;
  }

  // ── JSON (the app's own plan format) ──────────────────────

  static AiGoalResponse? _tryJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final before = raw.substring(0, start).trim();
    if (before.isNotEmpty &&
        !before.endsWith('```json') &&
        !before.endsWith('```')) {
      // JSON buried inside prose is more likely an example than the plan.
      if (before.split('\n').length > 3) return null;
    }
    try {
      final data = jsonDecode(raw.substring(start, end + 1));
      if (data is! Map<String, dynamic>) return null;
      final plan = AiGoalResponse.fromJson(data);
      return plan.milestones.isEmpty ? null : plan;
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ──────────────────────────────────────────────

  static String? _nextNonEmpty(List<String> lines, int i) {
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].trim().isNotEmpty) return lines[j];
    }
    return null;
  }

  static int _indentOf(String line) => line.length - line.trimLeft().length;

  static String _clean(String s) => s
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'\*\*|__|`|~~'), '')
      .replaceAllMapped(RegExp(r'(^|\s)[*_]([^*_]+)[*_](?=\s|$|[.,:;!?])'),
          (m) => '${m.group(1)}${m.group(2)}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static (String?, String) _splitEmoji(String s) {
    final m = _leadingEmoji.firstMatch(s);
    if (m == null) return (null, s);
    return (m.group(1)!.trim(), s.substring(m.end).trim());
  }

  static bool _looksLikeSection(String t) {
    if (t.endsWith(':') && t.length <= 80) return true;
    if (_sectionWord.hasMatch(t) && t.length <= 70 && !t.endsWith('.')) {
      return true;
    }
    final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
    return letters.length >= 3 &&
        t.length <= 40 &&
        letters == letters.toUpperCase();
  }

  static bool _isSkipped(String title) {
    final key = title
        .toLowerCase()
        .replaceAll(RegExp(r'[:.!]+$'), '')
        .replaceAll(RegExp(r'^\d+[.)]\s*'), '')
        .trim();
    return _skipSections.contains(key) ||
        key.startsWith('tips ') ||
        key.endsWith(' tips') ||
        key.startsWith('resources');
  }

  /// "Week 1: Foundations" → ("Week 1", "Foundations").
  static (String, String) _splitTitle(String text) {
    final m =
        RegExp(r'^(.{2,40}?)\s*(?::|\s[-–—|]\s)\s*(.+)$').firstMatch(text);
    if (m != null && _sectionWord.hasMatch(m.group(1)!)) {
      return (m.group(1)!.trim(), m.group(2)!.trim());
    }
    return (text, '');
  }
}

class _Builder {
  String? goalName;
  String? introGoal;
  String? emoji;
  final description = <String>[];
  final sections = <_Section>[];
  _Section? section;

  /// Any section came from a heading (not an outline bullet). Bullets with
  /// children are then tasks with notes, not new sections.
  bool explicitSections = false;
  bool skipping = false;
  _Task? lastTask;
  int lastTaskIndent = 0;

  bool get _hasGoal => goalName != null;

  void _setGoal(String text, {String? emojiHint}) {
    final (e, rest) = PlanTextParser._splitEmoji(text);
    emoji ??= e ?? emojiHint;
    final m = PlanTextParser._goalLabel.firstMatch(rest);
    goalName = PlanTextParser._capitalise(
        (m?.group(1) ?? rest).replaceFirst(RegExp(r'[:.]$'), '').trim());
  }

  void startSection(String text, {String theme = '', bool explicit = true}) {
    final (_, rest) = PlanTextParser._splitEmoji(text);
    var (title, t) =
        PlanTextParser._splitTitle(rest.replaceFirst(RegExp(r':\s*$'), ''));
    if (theme.isNotEmpty && t.isEmpty) t = theme;
    final s = _Section(
        title.length > 60 ? '${title.substring(0, 57)}…' : title, t,
        outline: !explicit);
    sections.add(s);
    section = s;
    skipping = false;
    lastTask = null;
    if (explicit) explicitSections = true;
  }

  _Section _ensureSection() {
    if (section != null) return section!;
    final s = _Section('Tasks', '', outline: false);
    sections.add(s);
    section = s;
    return s;
  }

  void heading(String text, {required bool maybeGoal}) {
    final (e, rest) = PlanTextParser._splitEmoji(text);
    final label = PlanTextParser._goalLabel.firstMatch(rest);
    if (label != null) {
      _setGoal(label.group(1)!, emojiHint: e);
      return;
    }
    if (PlanTextParser._isSkipped(rest)) {
      skipping = true;
      section = null;
      lastTask = null;
      return;
    }
    if (!_hasGoal && sections.isEmpty && maybeGoal) {
      _setGoal(text);
      return;
    }
    startSection(text);
  }

  void bullet(String text, {required int indent, required bool hasChildren}) {
    if (skipping) return;
    // Sub-points of a task become its notes.
    if (lastTask != null && indent > lastTaskIndent) {
      lastTask!.notes.add(text);
      return;
    }
    final (_, rest) = PlanTextParser._splitEmoji(text);
    if (PlanTextParser._goalLabel.hasMatch(rest)) {
      _setGoal(rest);
      return;
    }
    if (hasChildren && !explicitSections && indent <= 1) {
      startSection(text, explicit: false);
      section!.indent = indent;
      return;
    }
    final task = _ensureSection().addTask(text);
    if (task != null) {
      lastTask = task;
      lastTaskIndent = indent;
    }
  }

  static final _sectionLabel = RegExp(
    r'^(focus|theme|topic|objective|outcome|goal for this \w+|key skill|skills?)'
    r'\s*:\s*(.+)$',
    caseSensitive: false,
  );
  static final _metaLabel = RegExp(
    r'^(duration|time|time commitment|timeframe|estimated time|frequency)'
    r'\s*:\s*(.+)$',
    caseSensitive: false,
  );

  void plain(String text) {
    final (e, rest) = PlanTextParser._splitEmoji(text);
    // "Focus: …" under a heading describes the milestone, not a task.
    if (section != null) {
      final sl = _sectionLabel.firstMatch(rest);
      if (sl != null) {
        if (section!.theme.isEmpty) section!.theme = sl.group(2)!.trim();
        return;
      }
      if (_metaLabel.hasMatch(rest)) return;
    }
    final label = PlanTextParser._goalLabel.firstMatch(rest);
    if (label != null) {
      _setGoal(label.group(1)!, emojiHint: e);
      return;
    }
    if (PlanTextParser._looksLikeSection(rest)) {
      if (PlanTextParser._isSkipped(rest)) {
        skipping = true;
        section = null;
        lastTask = null;
        return;
      }
      if (!_hasGoal &&
          sections.isEmpty &&
          !PlanTextParser._sectionWord.hasMatch(rest)) {
        _setGoal(text);
      } else {
        startSection(text);
      }
      return;
    }
    if (skipping) return;
    if (!_hasGoal && sections.isEmpty) {
      if (rest.length <= 80) {
        _setGoal(text);
      } else {
        description.add(rest);
      }
      return;
    }
    if (sections.isEmpty) {
      description.add(rest);
      return;
    }
    // Inside a section: a short line is a step; a sentence of explanation
    // describes the section instead of cluttering the task list.
    final s = section;
    if (s == null) return;
    final isExplanation =
        rest.length > 90 || (rest.endsWith('.') && rest.split(' ').length > 10);
    if (isExplanation) {
      if (s.theme.isEmpty && s.tasks.isEmpty) {
        s.theme = rest.length > 60 ? '${rest.substring(0, 57)}…' : rest;
      }
      return;
    }
    final task = s.addTask(rest);
    if (task != null) {
      lastTask = task;
      lastTaskIndent = 0;
    }
  }

  AiGoalResponse build() {
    // "Day 1: …" lines with nothing under them are the plan itself.
    final empty = sections.where((s) => s.tasks.isEmpty).toList();
    if (sections.isNotEmpty && empty.length == sections.length) {
      final withTheme = empty.where((s) => s.theme.isNotEmpty).toList();
      sections.clear();
      if (withTheme.isNotEmpty) {
        final plan = _Section('Plan', '', outline: false);
        for (final s in withTheme) {
          plan.addTask('${s.title}: ${s.theme}');
        }
        sections.add(plan);
      }
    } else {
      for (final s in empty) {
        if (s.theme.isNotEmpty) s.addTask(s.theme);
      }
      sections.removeWhere((s) => s.tasks.isEmpty);
    }

    // "Milestone 1: Foundations" reads better as "Foundations".
    for (final s in sections) {
      if (PlanTextParser._genericTitle.hasMatch(s.title) &&
          s.theme.isNotEmpty) {
        s.title = s.theme;
        s.theme = '';
      }
    }

    var name = goalName ?? introGoal ?? 'Imported plan';
    if (name.length > 60) name = '${name.substring(0, 57)}…';

    return AiGoalResponse(
      goal: AiGoal(
        name: name,
        description: description.join(' '),
        emoji: emoji ?? '🎯',
        colorHex: '#5B9CF6',
        durationLabel: _duration(),
      ),
      milestones: [
        for (var i = 0; i < sections.length; i++)
          AiMilestone(
            title: sections[i].title,
            theme: sections[i].theme,
            order: i + 1,
            tasks: [
              for (var j = 0; j < sections[i].tasks.length; j++)
                AiTask(
                  text: sections[i].tasks[j].text,
                  priority: sections[i].tasks[j].priority,
                  order: j + 1,
                  note: sections[i].tasks[j].notes.join('\n'),
                ),
            ],
          ),
      ],
    );
  }

  String _duration() {
    final n = sections.length;
    if (n == 0) return '3 Months';
    final first = sections.first.title.toLowerCase();
    if (first.startsWith('week')) return '$n Week${n == 1 ? '' : 's'}';
    if (first.startsWith('month')) return '$n Month${n == 1 ? '' : 's'}';
    if (first.startsWith('day'))
      return n <= 7 ? '1 Week' : '${(n / 7).ceil()} Weeks';
    if (first.startsWith('quarter') || RegExp(r'^q[1-4]').hasMatch(first)) {
      return '${n * 3} Months';
    }
    return '3 Months';
  }
}

class _Section {
  _Section(this.title, this.theme, {required this.outline});
  String title;
  String theme;
  final bool outline;
  int indent = 0;
  final tasks = <_Task>[];

  static final _critical = RegExp(
    r'(\s*!!+\s*$|\s*[\(\[](critical|urgent|asap|must)[\)\]]|\b(urgent|asap)\b:?)',
    caseSensitive: false,
  );
  static final _high = RegExp(
    r'(\s*!\s*$|\s*[\(\[](high|important|priority|key)[\)\]]|^(important|key|priority):\s*|\s*⭐)',
    caseSensitive: false,
  );

  _Task? addTask(String raw) {
    var text = PlanTextParser._clean(raw);
    var priority = 0;
    if (_critical.hasMatch(text)) {
      priority = 2;
      text = text.replaceAll(_critical, '').trim();
    } else if (_high.hasMatch(text)) {
      priority = 1;
      text = text.replaceAll(_high, '').trim();
    }
    text = text.replaceFirst(RegExp(r'^[-–—:,.\s]+'), '').trim();
    if (text.isEmpty) return null;
    if (text.length > 200) text = '${text.substring(0, 197)}…';
    final task = _Task(PlanTextParser._capitalise(text), priority);
    tasks.add(task);
    return task;
  }
}

class _Task {
  _Task(this.text, this.priority);
  final String text;
  final int priority;
  final notes = <String>[];
}
