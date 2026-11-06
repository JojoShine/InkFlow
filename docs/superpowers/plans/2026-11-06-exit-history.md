# Windows Exit and History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow the execution method selected for the parent plan.

**Goal:** Reduce unnecessary exit work while preserving saved manuscripts, recoverable history and correct process teardown.

**Architecture:** Measure each existing exit phase before optimizing. Coalesce ordered history captures, track changed loaded records, then close local/network resources and the instance lease only after successful save preparation.

**Tech Stack:** Dart Stopwatch, existing HistoryStore/RecordStore, window_manager, Windows native runner.

**Spec:** [Sections 5 and 10](../specs/2026-11-06-windows-experience-and-ai.md). Depends on the demand-loading plan.

## Global Constraints

- 不通过删掉可靠写入、跳过保存、无限后台保存或强杀进程提速。
- 历史失败继续遵循现有“稿件已保存、历史未更新”提示语义。
- 历史初始化只能覆盖已加载记录，不得为了预热历史缓存读取全部云端内容。
- Normal local-disk targets: median save preparation below 500ms, window and process exit below 1s; measure rather than guarantee.
- Preserve the parent plan's constraints and all existing update-install safety behavior.

## Review Focus

- Concurrent timer/quit capture creates duplicate snapshots or caches failed writes (Task 1).
- Lazy work caches omit changed records or trigger full-cloud hydration (Task 1).
- Save failure leaves the window locked or releases the instance lease prematurely (Task 2).
- Old blocked file reads or the instance server keep a vanished window's process alive (Task 2).
- Antivirus/network delays exceed targets: show phase evidence, never weaken durability (Task 3).

### Task 1: Ordered, change-aware history

**Files:** Modify `lib/core/storage/history_store.dart`, `lib/features/notes/notes_controller.dart`, `lib/features/workbench/workbench_controller.dart`; extend `test/storage/history_store_test.dart`; create `test/workbench/changed_history_test.dart`.

**Interfaces:**
- Keep `HistoryStore.capture(String workKey, String recordId, List<int> bytes, DateTime now) -> Future<void>`; add `void invalidate(String workKey, String recordId)` and `Future<void> drain()`.
- Internally key queues/cache by both work and record; copy captured bytes at enqueue time. Cache latest hash plus retained entry metadata only after a successful write, bounded to the current work's loaded records; switching works drops unused entries after outstanding captures finish.
- `NotesController` exposes `Set<String> get pendingHistoryIds` and `void markHistoryCaptured(String id, RecordVersion version)`: removal must match the captured version so a newer edit stays pending. Controller captures changed loaded records, including changes saved by autosave and explicit external-update adoption.

- [ ] Write `unchanged_capture_does_not_rescan_history`, `concurrent_identical_capture_writes_once`, `failed_capture_is_retried`, `restore_invalidates_latest_hash`, `newer_note_edit_survives_capture_ack`, `lazy_exit_does_not_read_unloaded_records`. Add a test-only counting filesystem seam to HistoryStore if needed; production default remains current storage. Assert:
  ```dart
  expect(scansAfterSecondCapture, scansAfterFirstCapture);
  expect((await history.list(workKey, recordId)).length, 1);
  expect(notes.pendingHistoryIds, contains(newerEditedNoteId));
  ```
- [ ] Run `flutter test --no-pub test/storage/history_store_test.dart test/workbench/changed_history_test.dart`; verify the new scan/concurrency tests fail first.
- [ ] Implement per-record serialization, known-hash fast path and retained-entry pruning (100 distinct snapshots). Use a private disk-list helper so public `list` can invalidate cache for user inspection/recovery without invalidating internal capture bookkeeping. On corruption/I/O failure clear that key's cached state, preserve existing files, and allow retry.
- [ ] Replace `_snapshotAll` full-note iteration with current-body and pending loaded-note captures; ensure periodic capture, autosave and quit share tasks. Do not mark changes captured before successful history persistence. Preserve the before-edit snapshot on the first note mutation and the latest recoverable version.
- [ ] Run targeted tests plus `test/editor/autosave_test.dart`, `test/storage/record_store_test.dart`, `test/updates/update_safety_test.dart`; require PASS, including unchanged 100-version retention tests.
- [ ] Commit only Task 1 files: `perf: capture only changed loaded history records`.

### Task 2: Measurable, ordered quit preparation

**Files:** Modify `lib/main.dart`, `lib/features/workbench/workbench_controller.dart`, `lib/core/platform/instance_coordinator.dart` only if lease teardown requires correction; create `lib/core/platform/quit_preparation.dart`, `test/platform/quit_preparation_test.dart`; extend `test/updates/update_safety_test.dart`, `test/platform/instance_coordinator_test.dart`.

**Interfaces:**
- `WorkbenchController.beforeQuit: Future<bool> Function()?`; `prepareToQuit() -> Future<bool>` retains coalescing/lock/save behavior and invokes the hook only after successful manuscript preparation. A false/throwing hook resumes editing and does not release the lease.
- `QuitPreparation({required Future<bool> Function() save, required Future<void> Function() releaseLease, required Future<void> Function() destroyWindow}).run() -> Future<bool>` coalesces requests, releases then destroys only after save returns true. `releaseLease` is idempotent; surface teardown errors rather than silently claiming success.
- `QuitPhaseTiming` is a diagnostic callback `(String phase, Duration elapsed) -> void`, disabled by default; no content/path logging. Add phase measurement around existing calls rather than moving operations solely to improve the numbers.

- [ ] Add `quit_saves_before_hook_lease_and_destroy`, `save_failure_preserves_lease_and_unlocks_editor`, `concurrent_quit_shares_one_run`, `hook_failure_allows_retry`, `lease_close_releases_port_and_file_lock`. Assertions include:
  ```dart
  expect(events, ['save', 'hook', 'release', 'destroy']);
  expect(await rejectedQuit, isFalse);
  expect(c.session.isUpdateLocked, isFalse);
  expect(released, isFalse);
  ```
- [ ] Run `flutter test --no-pub test/platform/quit_preparation_test.dart test/updates/update_safety_test.dart test/platform/instance_coordinator_test.dart`; demonstrate RED before implementation.
- [ ] Implement coalesced preparation, phase timing, stopping watcher/index/read scheduling and `history.drain()` after save. Reuse version-matched computed word counts. Call `_instanceLease.close()` only for a successful quit; route native macOS requestQuit and Windows window-close paths through the same ordered teardown contract without recursive quit requests. Keep upgrade installation's allowed-quit sequence working.
- [ ] Run the above tests and `test/editor/editor_session_test.dart`, `test/updates/update_controller_test.dart`, demand-loading tests. Verify failure/retry paths restore watcher and editor operation, and no fallback `exit(0)` bypasses save.
- [ ] Commit Task 2 files: `fix: drain saves and release resources before desktop quit`.

### Task 3: Benchmark actual Windows close and process exit

**Files:** Add `tool/windows-exit-probe.ps1`; update `docs/verification/2026-11-06-desktop-experience.md`.

- [ ] Capture the parent commit baseline on the same Windows machine before applying timing-sensitive changes; preserve fixture and build configuration for comparison. Use no-work, unchanged, immediate-edits, 100 notes × 100 histories and 100k-character chapter fixtures.
- [ ] Run 10 closes per case before/after. Record phase durations, close-click to window disappearance, and close-click to process termination independently; include warm/cold history-cache state.
- [ ] Verify failed manuscript save refuses exit and keeps editing available. Confirm no global/cloud data warmup occurs to meet the timings; report any uninterruptible OS file read that delays process termination.
- [ ] Commit the reproducible probe and evidence: `test: measure Windows save and quit latency`.
