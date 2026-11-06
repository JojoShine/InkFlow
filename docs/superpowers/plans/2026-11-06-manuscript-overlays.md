# Windows Manuscript Overlays Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow the execution method selected for the parent plan.

**Goal:** Keep the Windows manuscript visible behind menus and dialogs without losing native editing state.

**Architecture:** Capture the existing RichEdit viewport into a Flutter image, paint it before hiding the native HWND, then restore HWND before removing the image. A paired begin/end overlay bridge handles nested overlays and stale capture replies.

**Tech Stack:** Win32 GDI/RichEdit, Flutter raw-pixel decoding, existing editor method channel.

**Spec:** [Section 4](../specs/2026-11-06-windows-experience-and-ai.md). Depends on demand-loading identity/generation semantics.

## Global Constraints

- 编辑器实例全程保留；不增加第二个可编辑副本。
- 展示期间正文不可编辑、不可滚动；点击菜单外部按浮层规则关闭，不穿透成为正文输入。
- 更新时保留上一份有效画面，不出现空白。
- Scale matrix: 100%, 125%, 150%, 200%; use the original paper/text colors, selection and scroll position.
- Preserve the parent plan's constraints; actual RichEdit capture needs Windows runtime evidence.

## Review Focus

- IME composition and selection at menu opening: no lost/repeated characters (Task 1).
- Theme/geometry/DPI changes while hidden: fresh pixels match restored editor (Task 2).
- Nested overlays close in different orders: HWND restored exactly once at depth zero (Task 2).
- Async capture outlives a chapter/window: ignore stale pixels and free resources (Task 2).
- Native HWND covers Flutter menu for even one visible transition: validate handoff on Windows, not just mocks (Task 3).

### Task 1: Native viewport snapshot contract

**Files:** Modify `windows/runner/native_novel_editor.h`, `native_novel_editor.cpp`; extend `tool/windows-editor-rendering-test.ps1`; create `test/editor/windows_snapshot_contract_test.dart`.

**Interfaces:**
- Method `snapshot` accepts `{documentId, documentGeneration}`; returns `{documentId, documentGeneration, width, height, rowBytes, scale, pixels}`. Dimensions are physical pixels, pixels are top-down BGRA8888 with opaque alpha, rowBytes is width × 4. It captures only the client viewport without caret; preserve native selection, scroll, IME and undo state.
- Native allocations are RAII-managed; invalid/stale document or unavailable surface returns an explicit channel error, not an empty successful image.

- [ ] Add bridge-contract tests for byte count/stride, stale generation, failure and correct scale. Extend the Windows probe with long paragraphs, scrolled viewport, IME, selection and hidden/configured editor cases; record current missing-method failure.
- [ ] Run `flutter test --no-pub test/editor/windows_snapshot_contract_test.dart`; confirm RED. Compile the native probe on Windows before accepting capture behavior.
- [ ] Implement GDI viewport rendering using `WM_PRINTCLIENT` into a memory DIB and validate actual RichEdit support; avoid capturing the entire desktop or Flutter dialog. Normalize alpha/orientation and preserve state. If capture does not render reliably, stop this component and report the evidence; do not ship a blank-image fallback as the fix.
- [ ] Run the contract test plus the Windows rendering probe; require correct pixels, unchanged manuscript/selection/scroll and no accumulated GDI objects across 100 open/close cycles.
- [ ] Commit only Task 1 files: `feat: capture Windows manuscript viewport for overlays`.

### Task 2: Flutter capture/visibility handoff

**Files:** Modify `lib/features/editor/novel_editor.dart`, `lib/features/editor/editor_session.dart`, `lib/app/ui_actions.dart`, `lib/features/workbench/work_actions_menu.dart`, `lib/features/appearance/appearance_panel.dart`, `lib/features/workbench/workbench_screen.dart`; create `lib/features/editor/editor_overlay.dart`, `test/editor/windows_overlay_transition_test.dart`.

**Interfaces:**
- `EditorSession.beginOverlay: Future<void> Function()?`, `EditorSession.endOverlay: void Function()?` are installed/removed with NovelEditor, like existing native callbacks. macOS retains current interaction behavior.
- `withEditorOverlay<T>(EditorSession session, Future<T> Function() show) -> Future<T>` awaits begin before showing and pairs end in finally. MenuAnchor uses the same paired callbacks around programmatic menu open/onClose; nested calls use a depth counter.
- `NovelEditor.overlayOpen` remains the compatibility route signal for callers that cannot preflight; prepare primary menu/dialog entry points before opening. Track capture generation, ready image and original focus. End only when both paired depth and compatibility route signal are clear.

- [ ] Write `snapshot_is_painted_before_native_hide`, `native_restores_before_snapshot_disposal`, `nested_overlays_restore_at_zero`, `stale_capture_is_discarded_after_chapter_change`, `capture_failure_keeps_dialog_operable`, `configuration_bursts_keep_one_inflight_capture`. Record channel calls and image readiness; assert:
  ```dart
  expect(events.indexOf('image-painted'), lessThan(events.indexOf('visible-false')));
  expect(events.indexOf('visible-true'), lessThan(events.indexOf('image-disposed')));
  expect(createdNativeEditors, 1);
  ```
- [ ] Run `flutter test --no-pub test/editor/windows_overlay_transition_test.dart`; verify RED.
- [ ] Implement raw-pixel image decoding, next-frame paint acknowledgement, native hide/show sequencing and image disposal. Refresh on effective 8-bit configuration/physical bounds changes, coalescing only the newest request; keep last valid pixels until replacement. Never reconstruct or reload the editor to close a dialog.
- [ ] Wrap the actual works-menu, appearance and existing modal entry points via the paired helper; preserve popup outside-click behavior. Capture failure reports a notice and uses the existing hidden-editor/dialog-operable path, marks feature validation failed, and does not deadlock overlay depth. Reset paired state on work/session disposal.
- [ ] Run new tests plus `test/editor/native_menu_interaction_test.dart`, `test/editor/native_busy_transition_test.dart`, `test/editor/native_configuration_stability_test.dart`, `test/editor/native_scroll_navigation_test.dart`; require PASS, including macOS no-regression cases.
- [ ] Commit Task 2 files: `fix: retain manuscript pixels behind Windows overlays`.

### Task 3: Validate native transitions

**Files:** Update Windows rendering probe and `docs/verification/2026-11-06-desktop-experience.md`.

- [ ] Run a Windows build and the spec's DPI/IME/theme/scroll matrix, including resizing during an open appearance dialog and fast successive work/chapter changes. Confirm the popup is never obscured by HWND and paper/text update together.
- [ ] Open and close works/appearance/AI-settings-compatible routes repeatedly; verify typing, undo, selection and focus afterward. Test captures during quit preparation and cancellation of a delayed chapter load.
- [ ] Record screenshots/timings and failures; commit evidence with `test: verify Windows manuscript overlay transitions`. No Windows environment means explicitly unverified, not complete.
