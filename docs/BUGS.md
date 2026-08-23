# RoadmapX — Bug Audit & Fixes

**Date:** 2026-08-23
**Scope:** full application scan (`lib/` — 73 source files), static analysis (`flutter analyze`) plus a manual logic review of every feature area: core services (backup, export, notifications, habit check-ins, schedule completion), database layer, AI integration, goals/milestones/tasks, schedule, today/dashboard, analytics, router, and shared widgets.

All bugs below were verified against the code before fixing. Status ✅ = fixed in this pass.

---

## High severity

### 1. ✅ Backup import corrupts all non-ASCII text (emoji, names, notes)
- **Where:** `lib/features/settings/presentation/settings_screen.dart` (`_importFromFile`)
- **Bug:** `String.fromCharCodes(pickedFile.bytes!)` decoded UTF‑8 bytes as raw char codes (Latin‑1). Backups are written as UTF‑8 and always contain multi-byte characters (every goal has an emoji, default 🎯).
- **Impact:** Importing a backup via the file picker turned every emoji / non-ASCII character into mojibake (🎯 → `ðŸŽ¯`) and wrote it permanently into the database.
- **Fix:** decode with `utf8.decode(...)`.

### 2. ✅ Gemini API key exported in plaintext to the shared Downloads folder
- **Where:** `lib/core/services/backup_service.dart` (`_exportablePreferences`)
- **Bug:** Every preference key — including `gemini_api_key` — was exported into `roadmapx_backup.json`, which on Android is written to the world-readable `/storage/emulated/0/Download` and re-written on every app resume.
- **Impact:** Secret leakage: any app/user with storage access could read the key; users sharing backup files to migrate devices leaked it too.
- **Fix:** sensitive keys are excluded from exports (`_sensitivePreferenceKeys`). Old backups containing a key still import fine.

### 3. ✅ Auto-restore looks for backups in a different place than they are written (Android)
- **Where:** `lib/core/services/backup_service.dart`
- **Bug:** Backups are written to `/storage/emulated/0/Download`, but the restore fallback scanned `getDownloadsDirectory()`, which on Android is the app-specific directory — wiped on uninstall. So after a reinstall (the exact scenario backups exist for) auto-restore never found the surviving backup. Additionally, scoped storage can forbid overwriting a file owned by a previous install, silently breaking every future backup.
- **Fix:** the restore fallback now scans the same directory the writer uses, and a failed write to shared Downloads falls back to the app directory instead of failing the whole backup.

### 4. ✅ Today & Dashboard screens show stale data after edits made elsewhere
- **Where:** `lib/features/tasks/providers/task_provider.dart`, `lib/features/tasks/data/task_repository.dart`
- **Bug:** `todayTasksGroupedProvider` awaited `watchAllTasks().first` — that consumes only the initial stream emission and never re-fires. Completing/deleting a task in Goal Detail (or any screen that didn't manually bump the refresh tick) left Today/Dashboard showing the old state until pull-to-refresh.
- **Impact:** Deleted tasks still visible, completed tasks still pending; tapping them acted on stale ids.
- **Fix:** added `watchTaskActivity()` / `watchGoalActivity()` (Isar `watchLazy`) streams and made all derived providers watch them, so any task/goal change recomputes automatically.

### 5. ✅ AI daily briefing gets stuck on an infinite spinner after any failure
- **Where:** `lib/features/ai_coach/providers/ai_coach_provider.dart` (`refresh`, `load`)
- **Bug:** `state = AsyncData(await _load(...))` with no error handling: any failure (offline, API error, malformed JSON) left the state as `AsyncLoading` forever and threw an unhandled async exception. The Retry button became a one-way trap.
- **Fix:** wrapped in `AsyncValue.guard(...)` so failures land in `AsyncError` and the UI's error/retry path works.

### 6. ✅ Date picker crash when editing an overdue goal
- **Where:** `lib/features/goals/presentation/widgets/create_edit_goal_sheet.dart` (also `create_edit_task_sheet.dart`, `create_edit_milestone_sheet.dart`)
- **Bug:** `showDatePicker(initialDate: storedDate, firstDate: DateTime.now())` violates the `initialDate >= firstDate` assertion whenever the stored target date is in the past — a routine state for goals. The task/milestone sheets had the same bug for dates > 1 year old.
- **Fix:** `firstDate` is clamped to never be after `initialDate` in all three sheets.

---

## Medium severity

### 7. ✅ A pending auto-backup could fire mid-restore and overwrite the backup file
- **Where:** `lib/core/services/backup_service.dart`
- **Bug:** `withoutScheduling` suspended *new* backup scheduling but didn't cancel an already-armed 3-second debounce timer, and the timer callback never re-checked the suspend flag. Editing a task then restoring within 3 seconds could overwrite the single `roadmapx_backup.json` (the file being restored from) with the pre-restore database.
- **Fix:** `withoutScheduling` cancels the pending timer, and the timer callback re-checks `_suspendScheduling`.

### 8. ✅ Restore fallback treated any `.json` in Downloads as "the latest backup"
- **Where:** `lib/core/services/backup_service.dart` (`_readLatestBackup`)
- **Bug:** No filename filter — on desktop, a freshly downloaded unrelated `config.json` would be "restored" (0 records) and its path cached as the latest backup.
- **Fix:** the scan now only considers files whose name contains `roadmapx` and ends in `.json`.

### 9. ✅ "Replace" restore kept stale per-day history from the device
- **Where:** `lib/core/services/backup_service.dart` (`_restorePreferences`)
- **Bug:** Replace mode cleared the four Isar collections but merged preferences, so `habit_checks_*` / `schedule_completion_*` days not present in the backup survived and polluted streaks/heatmaps.
- **Fix:** replace-mode restores remove existing per-day history keys first.

### 10. ✅ Habit streak displayed 0 every morning
- **Where:** `lib/core/services/habit_checkin_service.dart` (`getCurrentStreak`)
- **Bug:** The loop started at *today* and broke immediately if today was incomplete — which it always is at the start of a day — so a 30-day streak read as 0 until all 4 checks were done.
- **Fix:** an incomplete "today" is skipped (doesn't break the streak); the count starts from yesterday, matching the intent and the app's other streak logic.

### 11. ✅ Habit check-ins never rolled over at midnight
- **Where:** `lib/features/settings/providers/habit_checkin_provider.dart`, `lib/main.dart`
- **Bug:** The provider captured "today" once at build. Past midnight the UI kept showing yesterday's checks, and toggling wrote a value derived from yesterday's state onto the new day's key.
- **Fix:** `toggle()` detects the day change and re-reads today's stored checks; additionally the app now invalidates date-sensitive providers on the first resume of a new day (`_rolloverDayIfNeeded` in `main.dart`), which also fixes the Schedule screen's stale selected date.

### 12. ✅ Schedule day tabs showed impossible day numbers (32, 33, 34…)
- **Where:** `lib/features/schedule/presentation/schedule_screen.dart`
- **Bug:** Tab labels computed `weekStart.day + i` with plain integer addition — no month rollover. Every week spanning a month boundary showed numbers like 30, 31, 32, 33…
- **Fix:** the day number is normalized through `DateTime(...)`, so it rolls over correctly (30, 31, 1, 2…).

### 13. ✅ Week-start / day math unsafe across DST changes
- **Where:** `schedule_screen.dart`, `analytics_provider.dart`, `progress_utils.dart`, `date_utils.dart`, `today_task.dart`, `schedule_completion_service.dart`
- **Bug:** Widespread use of `subtract(Duration(days: n))` and `difference(...).inDays` on local dates. Across a DST transition local midnights are 23/25 hours apart: week starts landed on the wrong day, "due tomorrow" showed as "Due today", streaks broke, and the last-7-days histogram mis-binned.
- **Fix:** all calendar arithmetic now uses date-component math (`DateTime(y, m, d - n)`) and a new DST-immune `AppDateUtils.dayDifference()` (UTC-anchored).

### 14. ✅ Tasks due beyond the current calendar week were invisible on Today
- **Where:** `lib/core/models/today_task.dart` (`isDueThisWeek`)
- **Bug:** The "this week" bucket used a Monday-start calendar week. On a Sunday, a task due *tomorrow* fell into next week, matched no bucket, and vanished — the screen claimed "All caught up" while a task was due the next morning.
- **Fix:** the bucket is now "due within the next 7 days", so near-term tasks always appear.

### 15. ✅ Reordering goals while a filter was active corrupted the sort order
- **Where:** `lib/features/goals/data/goal_repository.dart` (`reorder`)
- **Bug:** The Goals screen passes the *filtered* list (default filter: Active), and `reorder` rewrote `sortOrder = 0..n-1` over that subset — colliding with the sortOrders of hidden (archived) goals and progressively scrambling the "All"/"Archived" views.
- **Fix:** the reordered visible goals are merged back into the position slots they occupied within the full list; hidden goals keep their relative order.

### 16. ✅ Deleting a goal from its detail screen triggered a double pop
- **Where:** `lib/features/goals/presentation/goal_detail_screen.dart`
- **Bug:** `_handleMenu` popped explicitly after delete, *and* the goal stream emitting `null` scheduled a second pop from the post-frame callback (which itself could fire multiple times across rebuilds). The user could be thrown back two screens or trigger a GoRouter error.
- **Fix:** the explicit pop was removed (the stream-null path is the single navigation mechanism) and the auto-pop is guarded by a once-only flag.

### 17. ✅ Deleting a goal left schedule items pointing at it forever
- **Where:** `lib/features/goals/data/goal_repository.dart` (`delete`)
- **Bug:** The cascade deleted milestones and tasks but never cleared `ScheduleItem.goalUid`, so linked schedule items silently lost their color/name/linked-tasks with no way to see why, and exports carried dangling uids.
- **Fix:** goal deletion now clears `goalUid` on linked schedule items inside the same transaction.

### 18. ✅ Weekly schedule notifications fired at the wrong hour after DST changes
- **Where:** `lib/core/services/notification_service.dart` (`_nextWeekdayTime`)
- **Bug:** `TZDateTime(...).add(Duration(days: n))` adds absolute time; crossing a DST change shifted the wall-clock hour, and the weekly repeat then fired an hour off until the next re-sync.
- **Fix:** days are added as date components, preserving the wall-clock hour.

### 19. ✅ Daily reminder drifted later every day
- **Where:** `lib/core/services/notification_service.dart` (`scheduleDailyReminder`)
- **Bug:** WorkManager periodic tasks schedule each run relative to the previous *execution*; Doze delays accumulate, so a 9:00 AM reminder drifted progressively later.
- **Fix:** the reminder is now a repeating `zonedSchedule` notification (`DateTimeComponents.time`) — the same reliable mechanism the app already uses for schedule events. The legacy WorkManager task is cancelled on reschedule.

### 20. ✅ Times written as "6.30 PM" never got a notification
- **Where:** `lib/core/services/notification_service.dart` (`_parseTime`)
- **Bug:** All dots were stripped before matching, turning `6.30 PM` into `630 PM`, which matched neither regex (whose `[:.]` alternation was therefore dead code) — the schedule item silently got no notifications.
- **Fix:** dots between digits are converted to `:` (time separator) before other dots (e.g. `P.M.`) are stripped.

### 21. ✅ Malformed AI responses crashed with `TypeError` instead of a friendly error
- **Where:** `lib/core/ai/gemini_service.dart`, `lib/core/ai/ai_coach_service.dart`
- **Bug:** Hard casts (`as Map<String, dynamic>`, `as List`, `as num?`) on model output: a top-level array, a missing `goal`/`milestones`/`tasks` key, or a `"85"` string score threw `TypeError`, bypassing both services' typed error handling ("Something went wrong" instead of "AI returned an unexpected format", plus bug #5's stuck spinner).
- **Fix:** parsing is defensive everywhere; shape mismatches surface as `GeminiException`/`AiCoachException`, and the score parser accepts numbers or numeric strings.

### 22. ✅ Failed AI-goal save left a partial goal; retry created a duplicate
- **Where:** `lib/features/ai_goal/providers/ai_goal_provider.dart` (`saveToDatabase`)
- **Bug:** The goal row was created first; if any later milestone/task insert failed, the half-saved goal remained and pressing "Save" again inserted a complete second copy. (The milestone sort also mutated the immutable state's list in place.)
- **Fix:** on failure the partially created goal is cascade-deleted before surfacing the error; the sort now operates on a copy.

### 23. ✅ Tapping "Try Again" within the cooldown destroyed the generated roadmap
- **Where:** `lib/features/ai_goal/providers/ai_goal_provider.dart` (`generate`)
- **Bug:** The cooldown branch set `result: null` with an error status — the preview vanished irrecoverably and the sheet fell back to the prompt view.
- **Fix:** if a successful preview exists, the early tap is ignored and the preview stays; otherwise the cooldown message no longer clears a prior result.

### 24. ✅ Restoring a backup didn't refresh AI settings or habit state until app restart
- **Where:** `lib/features/settings/presentation/settings_screen.dart`
- **Bug:** After restore/import only `settingsProvider` was invalidated. A restored API key/model and habit checks stayed invisible (AI features kept saying "No API key set"), and stale editor fields could silently overwrite restored values on blur.
- **Fix:** a shared `_invalidateRestoredProviders()` refreshes settings, AI settings, habit checks and activity ticks after both restore paths; the non-negotiables editor now syncs with external changes (`didUpdateWidget`) and only saves on blur when the user actually edited the field.

### 25. ✅ Tasks of archived goals still appeared on Today/Dashboard
- **Where:** `lib/features/tasks/data/task_repository.dart` (`getActiveTaskContexts`)
- **Bug:** Contexts were filtered only on `isCompleted`. Archiving an abandoned goal with 10 overdue tasks left all 10 stuck in "Overdue" with no way to clear them short of unarchiving.
- **Fix:** contexts belonging to archived goals are excluded (goal-scoped queries like the Focus screen are intentionally unaffected).

---

## Low severity

### 26. ✅ Undated tasks outranked urgent dated ones in "Next tasks" / Focus
- **Where:** `lib/features/tasks/data/task_repository.dart`
- **Bug:** Isar sorts null due dates *first*, so within the same priority a task with no due date beat one due today; the Focus query also lacked a stable tiebreaker.
- **Fix:** in-memory comparator — priority desc, then due date with nulls **last**, then manual sort order.

### 27. ✅ Notification ID ranges could collide at high row ids
- **Where:** `lib/core/services/notification_service.dart`
- **Bug:** `2000000 + id*10 + weekday` entered the next range's ID space at `id ≥ 100 000`, silently replacing other pending notifications.
- **Fix:** bases widened to 100 000 000 / 200 000 000 / 300 000 000 (collision now needs `id ≥ 10 000 000`; cancellation is payload-based so re-basing is safe).

### 28. ✅ Malformed deep link crashed route building
- **Where:** `lib/core/router/app_router.dart`
- **Bug:** `int.parse(state.pathParameters['goalId']!)` threw `FormatException` on `/goals/abc`.
- **Fix:** `int.tryParse(...) ?? 0`; id 0 matches no goal, and the detail screen pops back gracefully.

### 29. ✅ `ref`/context used after async gaps could throw when a widget was disposed mid-write
- **Where:** `schedule_screen.dart` (completion checkbox), `today_screen.dart` (task toggle), `ai_goal_sheet.dart` (save), `settings_screen.dart` (clear-all dialogs)
- **Fix:** `mounted` checks after every await that precedes `ref`/navigator/context use.

### 30. ✅ Schedule card kept showing another item's "Next tasks"
- **Where:** `lib/features/schedule/presentation/schedule_screen.dart` (`_ScheduleItemCard`)
- **Bug:** Linked tasks were loaded once in `initState` and the list item had no key, so when deletions shifted positions (or an item was relinked to another goal) a reused State displayed the old goal's tasks.
- **Fix:** cards are keyed by item uid and reload linked tasks in `didUpdateWidget`.

### 31. ✅ Changing the reminder time or task-due toggle was never backed up
- **Where:** `lib/features/settings/providers/settings_provider.dart`
- **Bug:** `setDailyReminderTime` / `setTaskDueNotificationsEnabled` were the only setters that didn't call `scheduleBackup()`.
- **Fix:** they do now.

### 32. ✅ "Clear All Data" left orphaned scheduled notifications
- **Where:** `lib/features/settings/presentation/settings_screen.dart` (`_clearAll`)
- **Bug:** Notifications scheduled for the deleted tasks/schedule items kept firing until the next app resume.
- **Fix:** notification syncs run with empty lists immediately after the wipe.

### 33. ✅ AI goal sheet didn't react to API-key changes
- **Where:** `lib/features/ai_goal/presentation/ai_goal_sheet.dart`
- **Bug:** It watched the repository provider (whose value never changes) instead of the settings notifier, so saving/clearing the key never rebuilt the sheet.
- **Fix:** watches `aiSettingsNotifierProvider`.

### 34. ✅ Schedule completion history included one extra day (off-by-one)
- **Where:** `lib/core/services/schedule_completion_service.dart` (`getCompletedDates`)
- **Fix:** cutoff computed with date components; window is exactly `lastDays` days including today.

### 35. ✅ Analyzer warnings: unused imports and variables
- **Where:** `app_router.dart`, `app_shell.dart`, `date_utils.dart`, `animated_checkbox.dart`, `color_picker.dart`
- **Fix:** removed. `flutter analyze` now reports **zero errors and zero warnings** in hand-written code.

---

## Known issues — documented, intentionally not changed

| # | Issue | Why not changed |
|---|-------|-----------------|
| A | **Merge-mode import never updates existing records** — a record whose uid already exists locally is skipped, so e.g. a task completed in the backup stays incomplete locally. | Plausibly intended "keep existing" semantics; changing it silently overwrites local edits. Needs a product decision (e.g. last-write-wins by timestamp). |
| B | **Web build: milestone completion celebration doesn't fire** — `IsarLink.value` doesn't lazy-load on web, so the confetti/haptic check can't resolve the milestone. | Web isn't a primary target; a proper fix needs explicit `link.load()` migration throughout the detail screen. |
| C | **~121 deprecation lints** (`withOpacity`, `background`, `surfaceVariant`, `onBackground`, `onReorder`, form-field `value`, …) | API migrations, not bugs — purely cosmetic today. Worth a dedicated cleanup pass before a Flutter upgrade makes them errors. |
| D | **A failed restore reports "No backup found to restore"** even when a backup exists but restoring failed. | Cosmetic message conflation; `BackupService` swallows the distinction. Low value relative to churn. |
| E | **Tasks due more than 7 days out still don't appear on Today** (buckets: overdue / today / next 7 days / no due date). | Deliberate scope of the Today screen; #14 fixed the actually-broken near-term case. |

---

## Verification

- `flutter analyze`: **0 errors, 0 warnings** in hand-written code (only info-level deprecations and generated-code lints remain).
- `flutter test`: all tests pass. *(Note: the suite currently contains only a placeholder test — adding real coverage for the streak/date/backup logic above is the highest-value next step.)*
