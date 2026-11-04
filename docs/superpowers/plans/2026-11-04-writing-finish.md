# Writing Finish Implementation Plan

> **For agentic workers:** Use executing-plans to implement inline; one scoped review at completion.

**Goal:** Add previewable, undoable whitespace formatting and local excerpt image sharing.
**Architecture:** Pure text transform + editor session/native edit bridge; pure Canvas PNG renderer + shared themed dialogs. Existing filesystem journal, history, desktop picker and manuscript state remain authoritative.
**Tech Stack:** Flutter/Dart, existing file_selector/characters, AppKit NSTextView and Win32 Rich Edit. No new packages.
**Spec:** docs/superpowers/specs/2026-11-04-polished-writing.md

## Constraints
- Original Songti font and Cupertino outline controls; local-first, no external publishing.
- Selected range or current chapter; preview/cancel is read-only; reject stale document/text/IME.
- Native edit must preserve undo and mark origin=format (excluded from typing metrics).
- PNG uses 1080px width, adaptive height, max 600 grapheme characters and no body truncation.
- Work in current dirty workspace; no unrelated changes or commits.

## Review focus
IME completion/stale async results; emoji/range boundaries; native undo continuity; image overflow/stale preview export; cancelled/unsafe file output.

## Task 1 — Format text and apply safely
Files: create lib/features/editor/text_formatting.dart, formatting_dialog.dart; modify editor_session.dart, novel_editor.dart, workbench_controller.dart, macos/Runner/NativeNovelEditor.swift, windows/runner/native_novel_editor.cpp. Tests: test/editor/text_formatting_test.dart and formatting_integration_test.dart.
- [x] Write pure transform/selection/idempotence tests; run RED.
- [x] Implement whitespace-only transform and changed-line counts.
- [x] Add native replaceRange bridge with expected document/text and single undo unit; fallback undo entry.
- [x] Preview options, before/after, selection/chapter scope; history snapshot and stale guards.
- [x] Run targeted tests and native AppKit undo probe.

## Task 2 — Share excerpt card
Files: create lib/features/sharing/share_card.dart, share_dialog.dart; modify core/platform/desktop_services.dart, app/ink_icons.dart, work_actions_menu.dart. Tests: test/sharing/share_card_test.dart, share_dialog_test.dart.
- [x] Write renderer/selection/validation/output tests; run RED.
- [x] Implement paper/night Canvas rendering with adaptive full text height and metadata.
- [x] Add debounced preview, excerpt/signature fields, style choices, copy text and PNG save.
- [x] Use existing RecordStore output protection; cancelled picker leaves content untouched.
- [x] Add both footer shortcuts beside statistics, remove repeated work-menu entries, and verify selection preservation at 960/1100/1360px.

## Task 3 — Verify and handoff
- [x] Full Flutter tests + analyze; scoped independent review and fix findings.
- [x] macOS build (sequential to tests); normal window-close/reopen UI verification.
- [x] Record limits/evidence in progress ledger; return concise user-facing instructions.
