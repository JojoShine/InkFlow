# Desktop Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execution method is pending user selection; do not dispatch agents before it is selected.

**Goal:** Deliver responsive shared-folder loading, faster reliable Windows exit, readable manuscript overlays and the AI discussion panel.

**Architecture:** Four independently testable plans share the existing repository, editor session and reliable save boundary. Implement lazy loading first, then exit/history, overlays and AI in that order; each later plan preserves loading-state semantics.

**Tech Stack:** Flutter/Dart, Win32 RichEdit, macOS AppKit/Keychain, existing file journal and atomic storage; Dart HTTP/SSE without vendor SDKs.

**Spec:** [Windows experience and AI design, including shared-folder addendum](../specs/2026-11-06-windows-experience-and-ai.md)

## Global Constraints

- AI 定位为思路整理、内容评价和总结。
- 现有作品格式版本仍为 1，不新增必须的共享索引文件，不要求原作品迁移。
- 全书字数不再驱动 TXT 读取。
- 保存失败时保留窗口、恢复编辑；未加载或不可用文件不得变成空稿。
- API Key 只保存到系统凭据，不进入作品、普通配置、对话、日志或备份。
- Only plan documents and the design addendum are changed at planning time; preserve unrelated website/release changes.
- Use temporary sample works and test credentials; report Windows/iCloud/provider verification gaps explicitly.

## Review Focus

- A delayed chapter response arrives after another chapter/work was selected: install only the newest result (loading Task 2).
- Cloud files disappear or arrive mid-refresh: preserve the last valid document and never create empty replacements (loading Tasks 1–3).
- Purge/export sees only the partial cache: hydrate required records explicitly and preserve all links/content (loading Task 3).
- Closing during save/AI streaming: drain writes, cancel reads/network, release locks only after the exit decision (exit Task 2; AI Task 5).
- Opening overlays with IME/changed DPI: preserve selection, composition and pixel alignment (overlay Task 1).

## Ordered plans

1. [Shared-folder demand loading](2026-11-06-demand-loading.md): lazy repository, staged UI, event refresh, partial-cache-safe operations.
2. [Windows exit and history](2026-11-06-exit-history.md): phase measurements, changed-record history, orderly teardown.
3. [Windows manuscript overlays](2026-11-06-manuscript-overlays.md): native viewport capture and visibility handoff.
4. [AI discussion panel](2026-11-06-ai-discussion.md): configuration/credentials, scoped messages, streaming, UI and persistence.

## Cross-plan contracts

- Loading owns `WorkLoadProgress`, `WorkReadCoordinator` and `WorkbenchController.chapterLoading`; later plans do not overload global `busy` or replace an unresolved editor session.
- Exit owns `WorkbenchController.beforeQuit: Future<bool> Function()?` as an optional preparation hook; AI installs a callback that cancels transport and flushes its local conversation. Hook failure returns to editing; invoke it before releasing the instance lease.
- Overlay owns `NovelEditor.overlayOpen`; later AI settings routes use the same modal/overlay tracking.
- AI owns `WorkbenchPanel {outline, character, inspiration, ai}`; only real notes map to `NoteKind`, with no file-format change.

## Final delivery

- [ ] Run each sub-plan's targeted tests after its changes; record red-to-green results and scoped commits.
- [ ] After all plans, run `flutter analyze` and `flutter test --no-pub`; zero errors/failures are required. Resolve dependencies explicitly once before checks; do not commit environment-only lockfile URL rewrites.
- [ ] Build macOS with `flutter build macos --debug --no-pub`; build Windows on a Windows runner with `flutter build windows --release --no-pub` after dependency setup. Builds and UI/native checks are sequential when sharing build outputs.
- [ ] Complete the native Windows/DPI/IME, iCloud offline/loading and five-provider matrix from the spec, or list precisely which are unverified. Do not call cross-platform functionality verified from mock-only tests.
- [ ] Record before/after timings and read counts in `docs/verification/2026-11-06-desktop-experience.md`; include build/OS, fixture size, observed limitations and reproducible commands.
- [ ] Review final changed files against user scope, verify unrelated work remains intact, then report completed behavior and remaining real-environment checks.
