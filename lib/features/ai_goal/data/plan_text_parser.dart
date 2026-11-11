import '../../../core/ai/gemini_service.dart';

/// Turns pasted text into a goal plan without any network call.
///
/// It understands the ways people usually write plans:
///
/// ```text
/// Learn Spanish                      ← first line: the goal
/// Get conversational by summer.      ← plain lines before sections: description
///
/// Week 1: Basics                     ← headings, "Week/Phase/Month N", or
///   - Learn 100 common words           lines ending in ":" become milestones
///   - Practise greetings !           ← bullets, numbers, checkboxes: tasks
/// ## Week 2                            ("!" / "(high)" / "urgent" = priority)
/// 1. Past tense
/// - [ ] Watch a film in Spanish
/// ```
///
/// Bullets that have their own indented bullets become milestones too. Tasks
/// with no section go into a "Tasks" milestone. Anything messier is what the
/// optional AI organiser is for.
class PlanTextParser {
  const PlanTextParser._();

  static final _heading = RegExp(r'^(#{1,6})\s+(.+)$');
  static final _bullet = RegExp(
    r'^(?:[-*•◦▪–—+>]|\d{1,3}[.)]|[a-zA-Z][.)])\s+(.+)$',
  );
  static final _checkbox = RegExp(r'^(?:\[[ xX✓]?\]|☐|☑|✅|✔️?)\s*');
  static final _sectionWord = RegExp(
    r'^(week|month|phase|day|step|stage|part|milestone|sprint|level|module|'
    r'chapter|section|quarter|q[1-4]|term|unit|round|block)\b\s*\d*',
    caseSensitive: false,
  );
  static final _leadingEmoji = RegExp(
    r'^((?:[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F000}-\u{1F2FF}]'
    r'[\u{FE0F}\u{200D}]?)+)\s*',
    unicode: true,
  );

  static AiGoalResponse parse(String raw) {
    final lines =
        raw.replaceAll('\r\n', '\n').replaceAll('\t', '    ').split('\n');

    String? goalName;
    final description = <String>[];
    final milestones = <_Section>[];
    _Section? current;

    _Section ensureSection() {
      if (current != null) return current!;
      final section = _Section('Tasks', '');
      milestones.add(section);
      current = section;
      return section;
    }

    void startSection(String text) {
      final split = _splitTitle(_clean(text));
      final section = _Section(split.$1, split.$2);
      milestones.add(section);
      current = section;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final t = line.trim();
      if (t.isEmpty) continue;
      final indent = line.length - line.trimLeft().length;

      // Markdown heading.
      final h = _heading.firstMatch(t);
      if (h != null) {
        final level = h.group(1)!.length;
        final text = h.group(2)!.trim();
        if (goalName == null &&
            milestones.isEmpty &&
            (level == 1 || !_sectionWord.hasMatch(text))) {
          goalName = _clean(text);
        } else {
          startSection(text);
        }
        continue;
      }

      // Bullet, numbered item or checkbox.
      final b = _bullet.firstMatch(t);
      final boxed = _checkbox.hasMatch(t);
      if (b != null || boxed) {
        final text = (b != null ? b.group(1)! : t).replaceFirst(_checkbox, '');
        if (text.trim().isEmpty) continue;
        // A bullet with its own indented children is a section.
        final next = _nextNonEmpty(lines, i);
        if (next != null &&
            indent <= 1 &&
            _indentOf(next) > indent &&
            (_bullet.hasMatch(next.trim()) ||
                _checkbox.hasMatch(next.trim()))) {
          startSection(text);
          continue;
        }
        ensureSection().addTask(text);
        continue;
      }

      // A plain line.
      if (_looksLikeSection(t)) {
        if (goalName == null &&
            milestones.isEmpty &&
            !_sectionWord.hasMatch(t)) {
          goalName = _clean(t.replaceFirst(RegExp(r':\s*$'), ''));
        } else {
          startSection(t.replaceFirst(RegExp(r':\s*$'), ''));
        }
        continue;
      }
      if (goalName == null) {
        goalName = _clean(t);
      } else if (milestones.isEmpty) {
        description.add(t);
      } else {
        // Prose inside a section reads as a step.
        current!.addTask(t);
      }
    }

    milestones.removeWhere((m) => m.tasks.isEmpty);

    var name = goalName ?? 'Imported plan';
    var emoji = '🎯';
    final e = _leadingEmoji.firstMatch(name);
    if (e != null) {
      emoji = e.group(1)!;
      name = name.substring(e.end).trim();
      if (name.isEmpty) name = 'Imported plan';
    }

    return AiGoalResponse(
      goal: AiGoal(
        name: name.length > 60 ? '${name.substring(0, 57)}…' : name,
        description: description.join(' '),
        emoji: emoji,
        colorHex: '#5B9CF6',
        durationLabel: _duration(milestones),
      ),
      milestones: [
        for (var i = 0; i < milestones.length; i++)
          AiMilestone(
            title: milestones[i].title,
            theme: milestones[i].theme,
            order: i + 1,
            tasks: [
              for (var j = 0; j < milestones[i].tasks.length; j++)
                AiTask(
                  text: milestones[i].tasks[j].$1,
                  priority: milestones[i].tasks[j].$2,
                  order: j + 1,
                ),
            ],
          ),
      ],
    );
  }

  static bool _looksLikeSection(String t) {
    if (t.endsWith(':') && t.length <= 80) return true;
    if (_sectionWord.hasMatch(t) && t.length <= 60) return true;
    // A short shouted line: "RESEARCH", "LAUNCH PREP".
    final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
    return letters.length >= 3 &&
        t.length <= 40 &&
        letters == letters.toUpperCase();
  }

  static String? _nextNonEmpty(List<String> lines, int i) {
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].trim().isNotEmpty) return lines[j];
    }
    return null;
  }

  static int _indentOf(String line) => line.length - line.trimLeft().length;

  static String _clean(String s) => s
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// "Week 1: Foundations" → ("Week 1", "Foundations").
  static (String, String) _splitTitle(String text) {
    final m = RegExp(r'^(.{2,40}?)\s*[:\-–—|]\s+(.+)$').firstMatch(text);
    if (m != null && _sectionWord.hasMatch(m.group(1)!)) {
      return (m.group(1)!.trim(), m.group(2)!.trim());
    }
    return (text.length > 60 ? '${text.substring(0, 57)}…' : text, '');
  }

  static String _duration(List<_Section> sections) {
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
  _Section(this.title, this.theme);
  final String title;
  final String theme;
  final tasks = <(String, int)>[];

  static final _critical = RegExp(
    r'(\s*!!+|\s*[\(\[](critical|urgent|asap)[\)\]]|\b(urgent|asap|critical)\b:?)',
    caseSensitive: false,
  );
  static final _high = RegExp(
    r'(\s*!$|\s*[\(\[](high|important|priority)[\)\]]|^important:?\s*)',
    caseSensitive: false,
  );

  void addTask(String raw) {
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
    if (text.isEmpty) return;
    if (text.length > 200) text = '${text.substring(0, 197)}…';
    tasks.add((text, priority));
  }
}
