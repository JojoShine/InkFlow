# AI Discussion Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow the execution method selected for the parent plan.

**Goal:** Add a self-configured AI tab for organizing ideas, evaluating attached writing and summarizing supplied content.

**Architecture:** A single Chat Completions client with provider presets feeds an isolated per-work conversation controller and themed panel. Settings persist separately from system credentials; immutable context attachments come only from a ready active editor session, and local conversation writes join orderly quit preparation.

**Tech Stack:** Flutter/Dart `HttpClient`, SSE, existing atomic storage/method channels, Windows Credential Manager and macOS Keychain; no vendor SDK/server.

**Spec:** [Sections 6–9 and 10](../specs/2026-11-06-windows-experience-and-ai.md). Depends on loading readiness, exit hook and overlay helper in the preceding plans.

## Global Constraints

- AI 定位为思路整理、内容评价和总结。
- 每部作品在本机保留一份当前对话；“新对话”清空当前对话前确认。
- 默认仅发送用户输入及当前对话历史。正文通过一次性的“选中文字 / 当前章节”附件主动加入。
- API Key 使用 Windows 凭据管理器、macOS 钥匙串；不退回明文保存。
- 完整 messages 的 UTF-8 文本总量上限 96KiB；超限阻止，不静默截断。
- 连接/首个 SSE 事件等待上限 60 秒，后续事件空闲上限 60 秒，总请求上限 5 分钟。
- Default output target 2048 tokens; HTTPS only, no credential-bearing redirects, no automatic retries or vendor switching.
- No automatic manuscript changes, rewrite/polish/continue-writing buttons, tools/search, uploads or multi-conversation management.

## Review Focus

- A custom URL change accidentally reuses an old provider's key (Task 1).
- A cloud-delayed chapter or edited selection supplies stale/incorrect material (Task 3).
- Chinese UTF-8/SSE boundary splits, empty usage chunks and reasoning-only events break streaming (Task 2).
- Work switch, new conversation or shutdown receives late tokens (Tasks 4–5).
- A provider error echoes a secret or partial local conversation save fails (Tasks 2, 4–5).

### Task 1: Provider settings and OS credential storage

**Files:** Create `lib/features/ai/ai_settings.dart`, `ai_settings_store.dart`, `ai_credentials.dart`, `windows/runner/ai_credentials.h`, `ai_credentials.cpp`, `macos/Runner/AiCredentials.swift`, `test/ai/ai_settings_test.dart`, `test/ai/ai_credentials_test.dart`; modify `windows/runner/flutter_window.h`, `flutter_window.cpp`, `windows/runner/CMakeLists.txt`, `macos/Runner/MainFlutterWindow.swift`, `macos/Runner.xcodeproj/project.pbxproj` to register sources/channels.

**Interfaces:**
- `AiProvider {deepseek, kimi, glm, qwen, openai, custom}` and immutable `AiSettings(provider, baseUrl, model)` contain no key. `Uri get completionUri`, `String get credentialId` use the same normalized URL identity.
- `AiSettingsStore(Directory root).load() -> Future<Map<AiProvider,AiSettings>>`, `.save(Map<AiProvider,AiSettings>) -> Future<void>` use a device-local `ai-settings.json`, serialized/atomic writes and schema version 1; active provider is optional until selected.
- `abstract interface class AiCredentials` has `read(String id) -> Future<String?>`, `write(String id, String key) -> Future<void>`, `delete(String id) -> Future<void>`. `PlatformAiCredentials` uses `inkflow/ai-credentials` methods read/write/delete with explicit success/error.
- Preset URLs exactly match the spec; Qwen requires user-supplied workspace/region replacement. Model ID remains a required editable field, not a remotely fetched catalog.

- [ ] Write `normalizes_base_without_duplicate_v1`, `rejects_non_https_credentials_query_fragment_and_placeholders`, `endpoint_change_requires_new_key`, `settings_json_contains_no_key`, `credential_failure_does_not_fallback_to_plaintext`. Test URL identity and fake credential calls; assert:
  ```dart
  expect(settings.completionUri.path, '/api/paas/v4/chat/completions');
  expect(serializedSettings, isNot(contains(secret)));
  expect(newEndpoint.credentialId, isNot(oldEndpoint.credentialId));
  ```
- [ ] Run `flutter test --no-pub test/ai/ai_settings_test.dart test/ai/ai_credentials_test.dart`; confirm RED.
- [ ] Implement settings validation/storage and the small native credential bridge. Namespace credentials to InkFlow; store per endpoint/provider. Save credentials before committing the nonsecret configuration, preserving the previous usable selection on failure. No key discovery, environment scanning or clipboard read.
- [ ] Run tests and native builds; use a disposable sentinel credential to verify read/write/delete and that failures return through the channel. On macOS verify signing/access behavior in a release-like build; report platform limitations.
- [ ] Commit only Task 1 files: `feat: store AI connection settings and system credentials`.

### Task 2: Shared streaming transport with provider adaptation

**Files:** Create `lib/features/ai/ai_client.dart`, `ai_provider_presets.dart`, `ai_stream_parser.dart`, `test/ai/ai_client_test.dart`, `test/ai/ai_stream_parser_test.dart`, `test/support/fake_ai_server.dart`.

**Interfaces:**
- Immutable `AiChatMessage(role, content)`; `AiEvent` variants `AiTextDelta(String text)`, `AiProcessing()`, `AiFinished(String reason)`, `AiFailed(AiFailure failure)`.
- `AiRequest` exposes `Stream<AiEvent> get events`, `Future<void> cancel()`; `AiClient.start(AiSettings settings, String key, List<AiChatMessage> messages) -> AiRequest`, `Future<void> close()`.
- `AiProviderPreset.buildBody(AiSettings settings, List<AiChatMessage> messages) -> Map<String,Object?>` owns role/output-limit/necessary provider parameter differences. Define verified text-model compatibility explicitly; do not silently substitute models or retry with different parameters.
- `FakeAiServer` is a loopback-only test fixture with scripted status, headers, split byte chunks, event delays and request capture. Production continues to reject HTTP endpoints; inject a test-only transport beneath URL validation for HTTP fixtures.

- [ ] Add tests `sse_preserves_split_chinese_and_emoji`, `handles_crlf_multiline_comments_and_done`, `usage_without_choices_is_valid`, `reasoning_events_reset_idle_timeout_without_entering_answer`, `truncated_stream_is_not_complete`, `stop_aborts_transport`, `json_success_is_supported`, `redirect_does_not_forward_authorization`, `error_echo_is_redacted`, `timeouts_are_60_60_300_seconds`. Include:
  ```dart
  expect(collectedAnswer, '线索🪶完整');
  expect(redirectTargetRequests, isEmpty);
  expect(displayedFailure, isNot(contains(secret)));
  expect(requestCountAfterFailure, 1);
  ```
- [ ] Run `flutter test --no-pub test/ai/ai_client_test.dart test/ai/ai_stream_parser_test.dart`; verify meaningful RED.
- [ ] Implement incremental UTF-8/SSE parsing, heartbeats, completion/refusal/length/error handling, timeout clocks and request abort. Use `HttpClient` with redirects disabled, TLS defaults intact, fixed required headers and cleaned error summaries; never log keys/messages. Handle empty delta/choices, `[DONE]`, explicit finish_reason and JSON fallback; unsupported tool responses fail clearly. Omit unsupported optional parameters rather than inventing a universal SDK config.
- [ ] Run targeted tests with deterministic fake clocks and loopback transport; assert cancelled request timers/subscriptions/clients are disposed and no auto retry occurs.
- [ ] Commit Task 2 files: `feat: stream compatible AI text responses`.

### Task 3: Purpose prompts and immutable manuscript attachments

**Files:** Create `lib/features/ai/ai_context.dart`, `ai_prompts.dart`, `test/ai/ai_context_test.dart`, `test/ai/ai_prompts_test.dart`; consume existing `EditorSession` and loading state without adding full-work readers.

**Interfaces:**
- `AiPurpose {organize, evaluate, summarize}`, `AiContextSource {conversation, selection, chapter}`.
- `AiAttachment(source, workKey, chapterId, chapterTitle, documentGeneration, text)` holds an immutable snapshot; character count uses graphemes for display, request budgeting uses UTF-8 bytes.
- `captureAiAttachment({required WorkbenchController controller, required AiContextSource source}) -> Future<AiAttachment?>`: refuse when chapterLoading, synchronize native composition, then recheck work/chapter/generation/selection before capturing. Conversation returns null; no selection never falls back to whole chapter.
- `buildAiMessages({required AiPurpose purpose, required List<AiChatMessage> completedHistory, required String question, AiAttachment? attachment}) -> List<AiChatMessage>` checks 96 × 1024 text bytes including role prompt; analysis modes require attachment or pasted nonempty source. The quick-action template is a draft until explicit send.

- [ ] Write `default_request_has_no_manuscript`, `selection_never_falls_back_to_chapter`, `native_sync_work_switch_rejects_stale_capture`, `loading_chapter_cannot_be_attached`, `unicode_ranges_do_not_split_surrogates`, `editing_after_attach_preserves_snapshot`, `history_budget_includes_prior_attachments`, `exact_96kib_boundary_is_accepted_and_plus_one_is_rejected`. Include:
  ```dart
  expect(defaultPayload, isNot(contains(manuscript)));
  expect(attachment.text, originalSelectedText);
  expect(() => oversizedMessages(), throwsFormatException);
  ```
- [ ] Run `flutter test --no-pub test/ai/ai_context_test.dart test/ai/ai_prompts_test.dart`; verify RED.
- [ ] Implement snapshot guards and three prompts: motivations/obstacles/causal options; limited evidence-based critique without generic scores; factual summary of supplied text only. Quote attached content as source material, distinct from instructions. Exclude unsuccessful/partial historical turns; include successful earlier attachments transparently. Attach once and reset draft scope after send; no implicit chapter/notes access.
- [ ] Run targeted tests plus native selection/editor-session tests. Manually review the three fixed templates against the spec; no request changes manuscript text or typing statistics.
- [ ] Commit Task 3 files: `feat: scope AI prompts to explicit writing context`.

### Task 4: Conversation state and local persistence

**Files:** Create `lib/features/ai/ai_conversation.dart`, `ai_conversation_store.dart`, `ai_controller.dart`, `test/ai/ai_conversation_store_test.dart`, `test/ai/ai_controller_test.dart`.

**Interfaces:**
- `AiTurn` contains stable message/request IDs, question, optional attachment, partial/final answer, timestamps and `AiTurnState {pending, receiving, completed, stopped, failed, interrupted}`; `AiConversation` contains schema version 1, bound provider/URL/model and turns.
- `AiConversationStore(Directory root).load(String workKey) -> Future<AiConversation?>`, `.save(String workKey, AiConversation conversation) -> Future<void>`, `.flush() -> Future<void>` use `ai/conversations/<workKey>.json`, serialized atomic saves and immutable enqueued snapshots.
- `AiController extends ChangeNotifier`: `activateWork(String? workKey)`, `send(String question, {required AiPurpose purpose, AiAttachment? attachment})`, `stop()`, `retry()`, `newConversation()`, `prepareToQuit()` return Future<void> except `prepareToQuit() -> Future<bool>`; `dispose()` invalidates generation and closes transport without requiring UI callbacks.

- [ ] Write `work_switch_cancels_and_ignores_late_tokens`, `new_conversation_invalidates_old_reply`, `retry_reuses_user_turn_without_duplicate`, `restart_marks_receiving_as_interrupted`, `partial_turns_do_not_enter_next_request`, `save_failure_preserves_visible_reply`, `stream_persistence_is_at_most_once_per_second_and_flushes_final`. Assert turn counts, request IDs and save times, not private implementation fields.
- [ ] Run `flutter test --no-pub test/ai/ai_conversation_store_test.dart test/ai/ai_controller_test.dart`; confirm RED.
- [ ] Implement transitions, work/connection/request identity checks, immutable persistence and 1-second partial-write throttle. Save the submitted user turn before network start; local save failure blocks that send until retry. A failed/corrupt conversation file is preserved and reported, never overwritten silently. Bind connection changes to explicit new-conversation confirmation at the UI boundary. Preserve model/endpoint on existing turns.
- [ ] Run tests including failed final save, stopped partial answer and restart. Ensure a post-cancel token cannot schedule a new local write or notify a disposed controller.
- [ ] Commit Task 4 files: `feat: persist isolated per-work AI conversations`.

### Task 5: AI tab, settings dialog and quit integration

**Files:** Create `lib/features/workbench/workbench_panel.dart`, `lib/features/ai/ai_panel.dart`, `ai_settings_dialog.dart`, `test/ai/ai_panel_test.dart`, `test/ai/ai_settings_dialog_test.dart`, `test/ai/ai_quit_test.dart`; modify `lib/features/notes/notes_panel.dart`, `lib/features/workbench/workbench_controller.dart`, `workbench_screen.dart`, `lib/app/ink_icons.dart` only for needed actions.

**Interfaces:**
- `WorkbenchPanel {outline, character, inspiration, ai}` with `NoteKind? get noteKind`; controller `panel`/`setPanel` use WorkbenchPanel, all note file models retain NoteKind. Share the tab header with NotesPanel; AI selection never dereferences note-only state.
- `AiPanel({required WorkbenchController workbench, required AiController controller, double width = 320})` and `showAiSettings(context, controller) -> Future<void>` follow existing theme/overlay helper conventions.
- Install `WorkbenchController.beforeQuit = aiController.prepareToQuit`; work changes await AI work activation without delaying first directory rendering on a remote model. Local conversation load is independent of shared-folder reads.

- [ ] Write `ai_tab_follows_inspiration_at_260px`, `quick_action_fills_draft_without_request`, `send_is_explicit_and_stop_preserves_partial`, `ime_enter_does_not_send`, `shift_enter_inserts_newline`, `unconfigured_state_opens_settings_only_on_click`, `attachment_shows_preview_remove_and_stale_hint`, `provider_change_confirms_new_conversation`, `settings_test_sends_only_fixed_test_message`, `quit_does_not_wait_for_model`, `failed_conversation_save_offers_retry_or_explicit_discard`. Assert no overflow, correct focus/semantics, no manuscript payload during connection test and no duplicate sends.
- [ ] Run `flutter test --no-pub test/ai/ai_panel_test.dart test/ai/ai_settings_dialog_test.dart test/ai/ai_quit_test.dart`; verify RED.
- [ ] Build the four-tab header, provider/model status, empty-state copy, three wrap-capable actions, selectable messages, attachment preview and multiline composer. Implement sending/processing/stopped/error hints and manual retry. Enter sends only outside IME composition; Shift+Enter inserts newline; loading disables attachment from an unresolved editor.
- [ ] Build settings with provider selection, editable URL/model, masked key, save/test/delete-key and actual endpoint display. Test connection explicitly sends one tiny message and explains that it is a model request. Clear the key input when the URL changes; never reuse old credentials for a new endpoint. Keep save-only offline.
- [ ] Integrate modal overlay pairing, connection-change/new-conversation confirmation, per-work activation and orderly quit hook. Save failure during quit offers retry or explicit discard of conversation changes while preserving manuscript save status. No-pending-change quit adds no network wait.
- [ ] Run AI tests plus `test/notes/notes_panel_test.dart`, `test/workbench/resizable_panels_test.dart`, `test/workbench/navigation_affordance_test.dart`, `test/updates/update_safety_test.dart` and demand-loading tests; require PASS. Update panel-selection tests where enum choice changed, preserving old note JSON snapshots.
- [ ] Commit Task 5 files: `feat: add AI discussion tab and connection settings`.

### Task 6: Provider and desktop acceptance

**Files:** Update `docs/verification/2026-11-06-desktop-experience.md`; update relevant user documentation only to describe delivered behavior.

- [ ] Run `flutter test --no-pub test/ai` and `flutter analyze`; build both supported desktop platforms. Verify real system credential persistence and the 260px/light/dark/IME matrix.
- [ ] With tester-supplied disposable API keys, verify each of DeepSeek/Kimi/GLM/Qwen/OpenAI for a short supplied Chinese sample: one conversation, streamed answer, manual stop, invalid key/error and follow-up history. Check preset-specific roles/output limits/model parameters against the official documentation linked in the spec. Missing keys mean unverified provider entries, not invented success.
- [ ] Check the three modes produce scoped responses and the manuscript/undo/word counts remain unchanged. Test current-chapter attachment in an iCloud fixture; only the ready session is read, with no hidden library scan.
- [ ] Record limits, costs incurred by explicit test requests if available from provider usage, and real-platform gaps without printing keys or private messages. Commit evidence: `test: record AI provider and desktop acceptance`.
