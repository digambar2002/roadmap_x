import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/gamification/progress_engine.dart';
import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/models/models.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/sound_service.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../../shared/widgets/page_title.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../pet/domain/pet_domain.dart';
import '../../pet/presentation/pet_avatar.dart';
import '../../pet/providers/pet_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../data/focus_sessions.dart';

enum _Phase { setup, running, paused, done }

/// A Pomodoro-style focus timer, with your pet keeping you company.
///
/// Sessions earn XP (and so coins) for every focused minute. The countdown
/// is anchored to an end time saved on the device, so it survives the app
/// being backgrounded or closed, and a notification marks the end.
class FocusTimerScreen extends ConsumerStatefulWidget {
  const FocusTimerScreen({super.key, this.taskId});

  /// Optional task to focus on.
  final int? taskId;

  @override
  ConsumerState<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends ConsumerState<FocusTimerScreen>
    with WidgetsBindingObserver {
  static const _durations = [15, 25, 45, 60];

  _Phase _phase = _Phase.setup;
  int _minutes = 25;
  Task? _task;
  DateTime? _start;
  DateTime? _endAt;
  Duration _remaining = const Duration(minutes: 25);
  Timer? _ticker;
  int _todayMinutes = 0;
  int _petNonce = 0;
  final _confetti = ConfettiController(duration: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _confetti.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back after the timer ran out in the background.
    if (state == AppLifecycleState.resumed && _phase == _Phase.running) _tick();
  }

  Future<void> _restore() async {
    final store = FocusSessions.instance;
    if (widget.taskId != null) {
      _task = await TaskRepository.instance.getById(widget.taskId!);
    }
    final running = await store.running();
    _todayMinutes = await store.minutesOn(DateTime.now());
    if (!mounted) return;
    if (running != null) {
      setState(() {
        _start = running.start;
        _endAt = running.endAt;
        _minutes = running.minutes;
        _phase = _Phase.running;
      });
      if (running.taskUid != null && _task == null) {
        final found =
            await TaskRepository.instance.getByUids([running.taskUid!]);
        if (found.isNotEmpty && mounted) setState(() => _task = found.first);
      }
      _startTicker();
    } else {
      setState(() {});
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  void _tick() {
    final end = _endAt;
    if (end == null) return;
    final left = end.difference(DateTime.now());
    if (left <= Duration.zero) {
      _finish();
    } else if (mounted) {
      setState(() => _remaining = left);
    }
  }

  Future<void> _begin() async {
    HapticFeedback.mediumImpact();
    final now = DateTime.now();
    _start = now;
    _endAt = now.add(Duration(minutes: _minutes));
    await FocusSessions.instance.setRunning(RunningFocus(
      start: now,
      endAt: _endAt!,
      minutes: _minutes,
      taskUid: _task?.uid,
      taskText: _task?.text,
    ));
    await NotificationService.instance
        .scheduleFocusEnd(_endAt!, taskText: _task?.text);
    SoundService.instance.play(Sfx.sparkle);
    setState(() => _phase = _Phase.running);
    _startTicker();
  }

  Future<void> _pause() async {
    _ticker?.cancel();
    await NotificationService.instance.cancelFocusEnd();
    await FocusSessions.instance.setRunning(null);
    setState(() {
      _remaining = _endAt!.difference(DateTime.now());
      _phase = _Phase.paused;
    });
  }

  Future<void> _resume() async {
    _endAt = DateTime.now().add(_remaining);
    await FocusSessions.instance.setRunning(RunningFocus(
      start: _start!,
      endAt: _endAt!,
      minutes: _minutes,
      taskUid: _task?.uid,
      taskText: _task?.text,
    ));
    await NotificationService.instance
        .scheduleFocusEnd(_endAt!, taskText: _task?.text);
    setState(() => _phase = _Phase.running);
    _startTicker();
  }

  Future<void> _finish() async {
    if (_phase == _Phase.done) return;
    _ticker?.cancel();
    final store = FocusSessions.instance;
    // The background settle may already have recorded it.
    final settled = await store.settleRunning(
        now: DateTime.now().add(const Duration(seconds: 1)));
    if (settled == null && _start != null) {
      await store.add(
          FocusSession(start: _start!, minutes: _minutes, taskUid: _task?.uid));
    }
    await store.setRunning(null);
    _todayMinutes = await store.minutesOn(DateTime.now());
    if (!mounted) return;
    bumpActivityTick(ref);
    HapticFeedback.heavyImpact();
    SoundService.instance.play(Sfx.fanfare);
    _confetti.play();
    setState(() {
      _phase = _Phase.done;
      _petNonce++;
    });
  }

  Future<void> _giveUp() async {
    final elapsed = _start == null
        ? 0
        : (_minutes - _remaining.inMinutes).clamp(0, _minutes);
    final ok = await ConfirmationDialog.show(
      context,
      title: 'End this session?',
      message: elapsed >= FocusSessions.minimumMinutes
          ? 'Your $elapsed focused minutes will still count.'
          : 'Sessions under ${FocusSessions.minimumMinutes} minutes are not counted.',
      confirmLabel: 'End session',
    );
    if (!ok) return;
    _ticker?.cancel();
    await NotificationService.instance.cancelFocusEnd();
    await FocusSessions.instance.setRunning(null);
    if (elapsed >= FocusSessions.minimumMinutes && _start != null) {
      await FocusSessions.instance.add(
          FocusSession(start: _start!, minutes: elapsed, taskUid: _task?.uid));
      if (mounted) bumpActivityTick(ref);
    }
    _todayMinutes = await FocusSessions.instance.minutesOn(DateTime.now());
    if (!mounted) return;
    setState(() {
      _phase = _Phase.setup;
      _remaining = Duration(minutes: _minutes);
    });
  }

  Future<void> _pickTask() async {
    final grouped = ref.read(todayTasksGroupedProvider).valueOrNull;
    final options = [
      ...?grouped?.overdue,
      ...?grouped?.dueToday,
      ...?grouped?.thisWeek,
      ...?grouped?.inbox,
    ];
    final picked = await showAdaptiveSheet<Task?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Focus on…',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.blur_on_rounded),
              title: const Text('Just focus'),
              onTap: () => Navigator.pop(sheetContext, null),
            ),
            for (final c in options)
              ListTile(
                leading: const Icon(Icons.radio_button_unchecked_rounded),
                title: Text(c.task.text),
                subtitle: Text(c.goal == null
                    ? 'Inbox'
                    : '${c.goal!.emoji} ${c.goal!.name}'),
                onTap: () => Navigator.pop(sheetContext, c.task),
              ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _task = picked);
  }

  Future<void> _completeTask() async {
    final t = _task;
    if (t == null || t.isCompleted) return;
    await TaskRepository.instance.toggleComplete(t.id);
    if (!mounted) return;
    bumpActivityTick(ref);
    setState(() => _task = t..isCompleted = true);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(1000).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pet = ref.watch(petViewProvider);
    final total = Duration(minutes: _minutes);
    final shown = _phase == _Phase.setup ? total : _remaining;
    final progress = _phase == _Phase.setup
        ? 0.0
        : _phase == _Phase.done
            ? 1.0
            : 1 -
                (_remaining.inMilliseconds / total.inMilliseconds)
                    .clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: cs.surface,
      body: AdaptivePage(
        child: SafeArea(
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  const PageTitle('Focus'),
                  const SizedBox(height: 4),
                  Text(
                    _todayMinutes > 0
                        ? '$_todayMinutes min focused today · '
                            '+${XpRules.focusMinute} XP per minute'
                        : 'Every focused minute earns XP and coins.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  // ── Timer ring ─────────────────────────────
                  Center(
                    child: SizedBox(
                      width: 250,
                      height: 250,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 12,
                              strokeCap: StrokeCap.round,
                              backgroundColor:
                                  cs.outline.withValues(alpha: 0.3),
                              valueColor: AlwaysStoppedAnimation(
                                _phase == _Phase.done
                                    ? const Color(0xFF10B981)
                                    : cs.primary,
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _phase == _Phase.done ? 'Done!' : _fmt(shown),
                                style: tt.displayMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              Text(
                                switch (_phase) {
                                  _Phase.setup => '$_minutes minutes',
                                  _Phase.running => 'Stay with it',
                                  _Phase.paused => 'Paused',
                                  _Phase.done =>
                                    '+${_minutes * XpRules.focusMinute} XP '
                                        '· +${_minutes * XpRules.focusMinute ~/ xpPerCoin} coins',
                                },
                                style: tt.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Pet company ────────────────────────────
                  if (pet != null)
                    Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            PetAvatar(
                              species: pet.species,
                              mood: _phase == _Phase.paused
                                  ? PetMood.content
                                  : PetMood.happy,
                              size: 130,
                              action: _phase == _Phase.done
                                  ? PetAction.love
                                  : PetAction.none,
                              actionNonce: _petNonce,
                            ),
                            if (_phase == _Phase.running)
                              const Positioned(
                                right: -6,
                                bottom: 18,
                                child:
                                    Text('💻', style: TextStyle(fontSize: 30)),
                              ),
                          ],
                        ),
                        Text(
                          switch (_phase) {
                            _Phase.setup => '${pet.name} will focus with you.',
                            _Phase.running =>
                              '${pet.name} is focusing with you.',
                            _Phase.paused => '${pet.name} is waiting.',
                            _Phase.done => '${pet.name} is proud of you!',
                          },
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  // ── Task ───────────────────────────────────
                  if (_phase == _Phase.setup)
                    OutlinedButton.icon(
                      onPressed: _pickTask,
                      icon: const Icon(Icons.task_alt_rounded, size: 18),
                      label: Text(
                          _task == null
                              ? 'Pick a task (optional)'
                              : _task!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    )
                  else if (_task != null)
                    Center(
                      child: Text('Focusing on: ${_task!.text}',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 16),
                  // ── Controls ───────────────────────────────
                  if (_phase == _Phase.setup) ...[
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        for (final m in _durations)
                          ChoiceChip(
                            label: Text('$m min'),
                            selected: _minutes == m,
                            onSelected: (_) => setState(() {
                              _minutes = m;
                              _remaining = Duration(minutes: m);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _begin,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start focus'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ] else if (_phase == _Phase.done) ...[
                    if (_task != null && !_task!.isCompleted)
                      FilledButton.icon(
                        onPressed: _completeTask,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Mark the task done'),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _phase = _Phase.setup;
                        _remaining = Duration(minutes: _minutes);
                      }),
                      child: const Text('Another round'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Done'),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _giveUp,
                            child: const Text('End'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _phase == _Phase.running ? _pause : _resume,
                            icon: Icon(_phase == _Phase.running
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                            label: Text(
                                _phase == _Phase.running ? 'Pause' : 'Resume'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              ConfettiWidget(
                confettiController: _confetti,
                blastDirectionality: BlastDirectionality.explosive,
                numberOfParticles: 30,
                shouldLoop: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
