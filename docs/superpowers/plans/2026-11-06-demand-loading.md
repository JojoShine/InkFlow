# Shared Folder Demand Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow the execution method selected for the parent plan.

**Goal:** Open and refresh large shared-folder works without reading every chapter or note, with immediate progress and recoverable failures.

**Architecture:** Preserve eager repository opening for existing tools; the workbench uses an explicit lazy mode. Manifest IDs drive directory placeholders, bounded metadata reads populate existing record maps, and a generation guard protects the single active editor session.

**Tech Stack:** Existing Dart file storage/journal, Flutter ListView and controller state; no cloud SDK or file-format migration.

**Spec:** [Sections 10 and 2](../specs/2026-11-06-windows-experience-and-ai.md)

## Global Constraints

- 现有作品格式版本仍为 1，不新增必须的共享索引文件，不要求原作品迁移。
- 章节信息每批最多 32 条，离屏预取最多一批；元信息读取最多 4 个并发。
- 笔记首次可见的资料页签每批检查最多 16 个文件。
- 全书字数不再驱动 TXT 读取。未知不是零；共享目录保存仍使用现有原子替换、版本冲突和操作日志。
- 等待超过 1 秒追加“文件读取较慢，云盘可能需要下载，请保持联网或稍后重试”。
- Preserve unrelated changes and the parent plan's save, credential and verification constraints.

## Review Focus

- Older chapter/work reads finish late: never install them into a newer session (Task 2).
- Missing cloud metadata/body is not an empty writable record (Tasks 1–2).
- A note's parent or a chapter's linked note is outside the loaded page: validate before mutation (Task 3).
- Focus/watch bursts and metadata changes with unchanged timestamps: hash-based save conflict protection still wins (Task 4).
- Export from a partial cache must include all eligible chapters (Task 3).

### Task 1: Lazy repository and bounded read scheduling

**Files:** Modify `lib/features/works/work_repository.dart`; create `lib/features/works/work_read_coordinator.dart`, `test/works/demand_loading_test.dart`, `test/support/controlled_record_store.dart`.

**Interfaces:**
- `WorkRepository.open(Directory root, {bool lazy = false, RecordStore? store}) -> Future<WorkHandle>`; pass the same store to journal recovery and the handle. Existing callers keep eager semantics.
- `WorkHandle` gains `bool get isLazy`, `Future<void> loadChapterMetadata(Iterable<String> ids)`, `Future<List<NoteRecord>> readNextNotes()`, `bool get notesComplete`, `int get notesChecked`, `int? get notesTotal`, `Future<void> ensureAllMetadata()`.
- `WorkReadCoordinator.run<T>(String key, Future<T> Function() read) -> Future<T>` coalesces same-generation metadata requests and limits active metadata reads to 4. `invalidate()` drops queued obsolete reads and starts a fresh generation without waiting on obsolete active reads; the limit of 4 includes obsolete active reads, while current-body reads bypass this metadata queue.
- Test `ControlledRecordStore extends RecordStore` exposes `List<String> reads`, `Set<String> blockedPaths`, `void release(String path)`, `int peakReads`. Override `read`; delegate unblocked reads to the real temporary fixture. Use the same store for note reads, removing direct note `readAsBytes` bypasses.

- [ ] Add tests named `lazy_open_reads_manifest_without_chapter_or_note_bodies`, `metadata_batches_and_concurrency_are_bounded`, `note_pages_examine_at_most_16_records`, `missing_records_never_create_replacements`. Create 1000 chapters with the existing eager API before installing the controlled store. Assertions include:
  ```dart
  expect(store.reads.where((p) => p.startsWith('chapters/')), isEmpty);
  expect(store.reads.where((p) => p.startsWith('notes/')), isEmpty);
  expect(work.chapters, isEmpty);
  expect(store.peakReads, lessThanOrEqualTo(4));
  expect(work.notesChecked, lessThanOrEqualTo(16));
  ```
- [ ] Run `flutter test --no-pub test/works/demand_loading_test.dart`; confirm failures describe missing lazy behavior, not a broken fixture.
- [ ] Implement lazy open, IDs-only manifest state, on-demand metadata/note enumeration, deduplication and queue limits. `readChapter(id)` ensures that chapter's real metadata before TXT; never fabricate `ChapterRecord`. `reload()` on an eager handle preserves existing behavior. Journal recovery remains a mandatory preceding phase.
- [ ] Run `flutter test --no-pub test/works/demand_loading_test.dart test/works/work_repository_test.dart test/storage/operation_journal_test.dart`; require all pass. Assert eager missing-metadata tests remain unchanged and pass.
- [ ] Commit only Task 1 files: `feat: add bounded lazy work repository reads`.

### Task 2: Progressive workbench opening and cancellable chapter selection

**Files:** Create `lib/features/workbench/work_load_progress.dart`, `test/workbench/demand_loading_test.dart`; modify `workbench_controller.dart`, `workbench_screen.dart`, `chapter_sidebar.dart`, `lib/features/notes/notes_panel.dart`, `lib/features/notes/notes_controller.dart`, `lib/features/editor/novel_editor.dart` only where loading requires input gating.

**Interfaces:**
- Define `WorkLoadStage {directory, recovery, chapter, notes, refresh}` and immutable `WorkLoadProgress(stage, {String? targetId, int? completed, int? total, bool slow = false, String? error})`.
- Controller exposes `WorkLoadProgress? get loadProgress`, `bool get chapterLoading`, `List<String> get directoryChapterIds`, `bool get totalWordsComplete`, `Future<void> loadVisibleChapters(Iterable<String> ids)`, `Future<void> loadMoreNotes()`, `void cancelLoad()`, `Future<void> retryLoad()`.
- Preserve `selectChapter(String id) -> Future<void>`; capture generation/work/target before reading, flush the old session before installing the new document. Keep `activeChapter` and editor title on the old chapter until installation succeeds. Remove the long read phase from the serialized library-write queue without allowing writes to reorder.

- [ ] Add widget/controller tests `first_frame_names_loading_phase`, `slow_read_shows_waiting_hint_after_one_second`, `old_chapter_reply_cannot_replace_new_selection`, `cancel_or_failure_preserves_old_draft`, `unknown_total_is_not_zero`, `directory_requests_only_visible_batch`. Block selected TXT with the Task 1 fixture and use fake time for the 1-second hint. Assertions include:
  ```dart
  expect(c.activeChapterId, oldChapterId);
  expect(c.session.controller.text, oldText);
  expect(c.chapterLoading, isTrue);
  expect(c.totalWordsComplete, isFalse);
  expect(find.textContaining('全书未统计', findRichText: true), findsOneWidget);
  ```
- [ ] Run `flutter test --no-pub test/workbench/demand_loading_test.dart`; observe expected failure before implementation.
- [ ] Install the lazy repository in `openWork`; publish directory/recovery progress before awaiting I/O. Replace `_indexWords` with counting only current/explicitly read documents. Build directory rows from manifest IDs, request at most 32 visible metadata records plus one prefetch batch, and show placeholders/loading/errors. Load the remembered chapter first or search first available chapter in order; missing target is a retryable state, not a new empty chapter.
- [ ] Add per-request cancellation/generation and timers disposed on completion; cancellation abandons reads and queued work but never cancels writes. Keep old editor read-only only while its safe replacement is being committed; a failed/cancelled selection restores editing. Notes show checked/total and an explicit next-batch affordance; no empty-category claim until all files are examined. Route load failures into local retry controls rather than a silent spinner.
- [ ] Run `flutter test --no-pub test/workbench/demand_loading_test.dart test/workbench/workbench_test.dart test/workbench/volume_sidebar_test.dart test/notes/notes_panel_test.dart test/editor/focus_mode_test.dart`; require all pass, updating assumptions about partial caches only where this feature changes behavior.
- [ ] Commit Task 2 files: `feat: show progressive work and chapter loading`.

### Task 3: Keep mutations, recovery and exports correct with partial caches

**Files:** Modify `lib/features/works/work_repository.dart`, `lib/features/notes/notes_controller.dart`, `lib/features/transfer/text_transfer.dart`, `lib/features/recovery/recovery_panel.dart`, `lib/features/workbench/workbench_controller.dart`, `lib/features/transfer/transfer_dialogs.dart`; create `test/works/lazy_mutations_test.dart`, extend `test/transfer/text_transfer_test.dart`, `test/transfer/backup_service_test.dart`.

**Interfaces:**
- Use `ensureAllMetadata()` only for user-requested operations needing a complete set (full export, recycle-bin enumeration, cross-record purge); this loads JSON records, never all TXT.
- Add `WorkHandle.readNote(String id) -> Future<NoteRecord>` and `WorkHandle.ensureOutlineAncestors(String id) -> Future<void>`; retain real versions in `_versions` before saving.
- `NotesController.loadNextPage() -> Future<void>` delegates to `readNextNotes`; `ofKind` returns only loaded matches. Add `bool get hasUnexaminedNotes` for UI. Mutation entry points validate target/ancestor metadata explicitly; classify chapters from manifest IDs, not loaded-map membership.

- [ ] Add tests `purge_unloaded_chapter_clears_unloaded_note_links`, `outline_parent_outside_page_is_validated`, `missing_parent_is_not_silently_detached`, `export_includes_unloaded_chapters`, `backup_from_lazy_handle_keeps_complete_sources`. Include assertions:
  ```dart
  expect(exported, contains('尚未打开的章节正文'));
  expect(reopened.notes[linkedNoteId]!.chapterId, isNull);
  expect(await originalBody.readAsString(), originalText);
  ```
- [ ] Run `flutter test --no-pub test/works/lazy_mutations_test.dart test/transfer/text_transfer_test.dart test/transfer/backup_service_test.dart`; first demonstrate partial-cache failures.
- [ ] Implement on-demand target/ancestor reads, full-set loading only at explicit complete operations, and operation-phase feedback. Audit `chapters[id]!`, `notes.containsKey`, `liveChapters` consumers in sidebar/controller/recovery/transfer: unknown entries must not be omitted or classified as another record type. Keep mutation journal/version checks and existing backup source revalidation.
- [ ] Run the above tests plus `test/works/volumes_test.dart`, `test/works/work_repository_test.dart`, `test/storage/record_store_test.dart`; require all pass and no new format fields.
- [ ] Commit Task 3 files: `fix: preserve complete operations with lazy work caches`.

### Task 4: Refresh only invalidated/visible records

**Files:** Modify `lib/features/works/work_repository.dart`, `lib/features/workbench/workbench_controller.dart`; create `test/workbench/targeted_refresh_test.dart`.

**Interfaces:**
- `WorkHandle.reload({Set<String>? changedPaths}) -> Future<void>`: lazy handles refresh manifest/affected loaded metadata, invalidate unseen entries without hydrating them; eager handles retain full validation.
- Controller adds `Future<void> refreshDirectory()`; watcher batches normalized relative paths, checks one refresh at a time and schedules one follow-up when new events arrive. A generation check precedes each state install. Keep `checkExternal() -> Future<void>` for focus, using file state of manifest and loaded records only.

- [ ] Write tests `unseen_txt_change_invalidates_count_without_read`, `watch_burst_coalesces_and_late_event_is_not_lost`, `dirty_current_document_survives_external_change`, `focus_does_not_index_unknown_chapters`, `missing_cloud_record_keeps_last_good_state`, `save_conflict_uses_hash_even_when_stat_is_unchanged`. Assert the controlled store never reads the unseen TXT and conflict output retains both versions.
- [ ] Run `flutter test --no-pub test/workbench/targeted_refresh_test.dart`; verify RED.
- [ ] Remove the unknown/changed-count TXT loop from `checkExternal`; invalidate counts on events and only read the current body when necessary. Refresh visible metadata/notes, retain dirty note drafts with their base versions, and do not read all note bodies on focus. Add a refresh-directory action that re-enumerates IDs/file names, not content. Keep conflict-copy discovery separate from reading comparison contents.
- [ ] Run targeted refresh, demand loading, autosave and record-store tests; require PASS. Assert no active watch/timer work after dispose or exit-preparation cancellation.
- [ ] Commit Task 4 files: `perf: refresh shared works by changed record`.

### Task 5: Record real shared-folder behavior

**Files:** Create/update `docs/verification/2026-11-06-desktop-experience.md`; add a disposable-fixture entry point `tool/demand_loading_probe.dart` only if the existing test fixture cannot drive the native app.

- [ ] Run the complete loading-related tests and `flutter analyze`; record results.
- [ ] On macOS/iCloud and Windows shared folders, measure first directory frame, active chapter readiness and requested-file count with 1000 chapters, cached files, cloud placeholders, offline and reconnection. Verify return-to-library and retry while reads are delayed; never use real manuscripts.
- [ ] Confirm application file requests are bounded separately from OS-initiated hydration. Report unavailable environments as unverified, with the exact manual steps needed.
- [ ] Commit the measurement evidence with `docs: record shared-folder loading verification`.
