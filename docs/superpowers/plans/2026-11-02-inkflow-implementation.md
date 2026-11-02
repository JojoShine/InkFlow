# InkFlow 首版 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 Windows 与 macOS 上可离线使用、可换肤、有恢复能力的轻量小说写作工作台。

**Architecture:** Flutter 桌面单应用，按作品、编辑、资料、外观组织代码。作品文件夹保存可迁移内容，设备应用数据目录保存偏好与历史；编辑会话不依赖主题，存储按记录串行写入并检测外部版本。

**Tech Stack:** 本机 Flutter 3.41.9 / Dart 3.11.5；Flutter 自带 ChangeNotifier、Actions、Shortcuts 和编辑基础设施；dart:io 文件系统；file_selector、path_provider、path、characters、crypto、archive、charset_codec；window_manager 固定 0.5.1。测试使用 flutter_test、fake_async、integration_test。依赖在初始化时解析兼容版本并提交 pubspec.lock，不自动升级 Flutter。

**Spec:** [InkFlow 首版需求与设计](../specs/2026-11-02-inkflow-design.md)，已获用户确认。

## Global Constraints

- 使用 Flutter 构建 Windows 和 macOS 桌面应用。
- 本地优先，无需账号即可离线写作。
- 应用主题与编辑排版分别保存。
- 主题、壁纸和排版偏好按设备保存，允许不同屏幕使用不同设置；作品内容随作品文件夹迁移和同步。
- 输入停止 1 秒后触发保存；持续输入时至少每 10 秒尝试持久化一次。持久化过程不刷新编辑控制器或打断输入法组合状态。
- 每条正文或资料记录保留最近 100 个快照，当前稿件与尚未处理的冲突副本不参与快照淘汰。
- 回收站内容由用户明确永久删除，首版不自动清空。
- 同一台电脑上，同一作品只允许一个编辑实例，第二个打开请求转到已有实例。
- 界面字数按 Unicode 字素簇计数，排除空格、换行和其他空白，标点计入。
- 在固定验收机器上，非输入法候选窗口操作的按键到可见文字延迟 p95 不超过 100 毫秒，章节切换不超过 1 秒。

执行范围：本计划尚未执行。先审阅计划并选择执行方式，再开始任务 1；任务 1 的视觉方案需用户审阅，任务 2 的编辑验证需通过，才扩展正式工作台。执行中保留用户选择的方式，不自行切换为多代理。

## Review Focus

1. 输入法组合状态下自动保存、换肤或切章：保留输入，正常确认候选，撤销边界正确；任务 2、6、11 验证。
2. 网盘延迟、清单冲突副本、同内容不同时间戳：保留双方实际内容，不根据时间戳选新版；任务 4、8 验证。
3. 写入中止、目录突然失效或第二实例启动：已有有效稿件不损坏，未保存内容仍可另存；任务 4、5、11 验证。
4. 表情、罕见汉字、不同换行与损坏编码：字数一致、导出无隐形缩进字符、导入不静默丢字；任务 2、3、9 验证。
5. macOS 重启后目录授权、Windows 中文路径及大小写别名：能重新访问同一作品，不能绕过同机编辑实例约束；任务 5、11 验证。

## 文件与数据边界

以下路径相对项目根目录；新文件只在所属任务开始时创建。

| 路径 | 职责与首次任务 |
| --- | --- |
| docs/design/visual-direction.md；docs/design/previews/ | 工作台、主题、专注状态视觉参考，任务 1 |
| pubspec.yaml；pubspec.lock；analysis_options.yaml；lib/main.dart；lib/app/inkflow_app.dart | 桌面工程与依赖，任务 2 |
| lib/features/editor/novel_editor.dart；editor_session.dart；paragraph_layout.dart | 输入、会话与纯显示排版，任务 2、6 |
| docs/verification/editor-probe.md | 编辑器可行性和性能证据，任务 2 |
| lib/features/works/work_models.dart；work_codec.dart；work_repository.dart | 作品记录、格式、生命周期，任务 3、4 |
| lib/core/storage/local_file_store.dart；record_store.dart；operation_journal.dart | 文件替换、版本与多记录恢复，任务 4 |
| lib/core/storage/history_store.dart；recovery_store.dart | 本地历史与未完成会话恢复，任务 5 |
| lib/core/platform/desktop_services.dart；instance_coordinator.dart | 目录、窗口、授权与同机单实例，任务 5 |
| macos/Runner/DirectoryAccess.swift；macos/Runner/AppDelegate.swift；macos/Runner/*.entitlements | 持久目录授权及平台接入，任务 5 |
| lib/features/preferences/device_preferences.dart；preferences_store.dart | 设备偏好与恢复位置，任务 5、7 |
| lib/features/appearance/appearance_settings.dart；theme_presets.dart；appearance_controller.dart；appearance_panel.dart；wallpaper_layer.dart | 主题、壁纸与预览，任务 7 |
| lib/features/workbench/workbench_controller.dart；workbench_screen.dart；chapter_sidebar.dart；status_bar.dart | 工作台与章节操作，任务 8 |
| lib/features/library/library_screen.dart | 书架、新建、打开、目录失效处理，任务 8 |
| lib/features/notes/note_models.dart；notes_controller.dart；notes_panel.dart | 大纲、角色、灵感，任务 8 |
| lib/features/recovery/recovery_panel.dart；conflict_panel.dart | 历史、回收站和冲突选择，任务 8 |
| lib/features/transfer/text_transfer.dart；backup_service.dart；transfer_dialogs.dart | TXT 与完整备份，任务 9 |
| integration_test/；test/；tool/；docs/verification/desktop-acceptance.md | 场景验证、样本、双平台记录，任务 2 至 11 |

作品目录格式固定为：`work.json` 保存 formatVersion、workId、书名与有序 chapterIds；`chapters/<id>.json` 保存标题、删除状态；`chapters/<id>.txt` 保存正文；`notes/<id>.json` 保存带 kind 的创作资料；`.inkflow/operations/` 保存未完成操作记录；`.inkflow/conflicts/` 保留双方冲突副本。回收站是记录的 deletedAt 状态，不另建正文副本。

所有 ID 使用安全随机生成的 128 位十六进制值。路径只由 ID 构造，不使用标题拼接路径。清单 formatVersion 首版为 1；未知版本只提示不兼容，不写回。作品元数据和正文版本均以原始字节 SHA-256 判断，不依赖修改时间。本机数据以规范化作品路径与 workId 共同分区，复制出来的作品不共享编辑锁或本地历史。

## Task 1 视觉方案

**Files:** 创建 `docs/design/visual-direction.md`、`docs/design/previews/workbench-warm.svg`、`workbench-night.svg`、`appearance-panel.svg`、`focus-mode.svg`。

**Interfaces:** 输入设计文档第 3、5 节；输出可审阅的四张桌面参考图和界面尺寸、颜色、字体层级、状态说明，供任务 7、8 使用。

- [ ] 按 1440×900 设计暖色工作台：目录宽 216、资料面板宽 280、正文最大宽 720；可收起，工具按钮有文字提示。主背景 #F3EFE7、编辑区 #FFFDF8、正文 #302C27、强调色 #8B6245，最终以可读性检查调整。
- [ ] 绘制同结构低亮度主题、打开的外观面板、专注模式；文字使用真实中文小说样例，显示实际菜单、字数和保存状态，不堆放装饰卡片。壁纸示例用本地原创矢量纹理，上传照片的能力在任务 7 实现。
- [ ] 在视觉说明中定义 1280×800 及 150% 系统缩放：空间不足优先收起右侧资料，正文最小可用宽 480；正常窗口最小宽 960、高 640，保证菜单可滚动到全部项目。
- [ ] 检查正文与底色对比度至少 4.5:1、状态不只靠颜色、按钮有键盘焦点；展示图交由用户审阅。视觉任务无需镜像实现的单元测试。
- [ ] 获得视觉反馈后更新参考图和说明；记录通过的版本。图稿未获认可时，继续调整图稿，先不实现界面。

## Task 2 桌面工程与编辑器验证

**Files:** 创建工程根文件与 `macos/`、`windows/`、`lib/main.dart`、`lib/app/inkflow_app.dart`、编辑器三个源文件、`test/editor/novel_editor_test.dart`、`tool/generate_manuscripts.dart`、`docs/verification/editor-probe.md`。

**Interfaces:** `NovelEditor({required EditorSession session, required EditorLayoutSettings layout})`；`EditorLayoutSettings({String? fontFamily, double fontSize = 20, double lineHeight = 1.8, double paragraphGap = 8, double firstLineIndentEm = 2, double maxWidth = 720})`。后续任务保持组件身份与会话对象稳定；不以换肤重新创建编辑控制器。

- [ ] 检查 `flutter doctor -v`；在临时空目录执行 `flutter create --platforms=macos,windows --project-name inkflow`，检查生成内容后复制工程文件，保留现有 docs。只在开始实现时初始化本项目 Git；不自动创建远程仓库。
- [ ] 解析并锁定依赖，`window_manager: 0.5.1`，`charset_codec: 0.1.1`。其他依赖使用与 SDK 兼容的稳定版，保存 lock；运行 `flutter analyze` 和初始 `flutter test`。GB18030 依赖无法通过样本验证时先修正依赖方案，不降级为 GBK 或替换字符。
- [ ] 写编辑验证用例 `composing_survives_style_change`：输入带 composing range 的 `TextEditingValue`，更换显示设置后断言 text、selection、composing 不变；`layout_never_inserts_indent_characters`：文本“第一段\n第二段”在调整缩进和段间距后，导出的原文仍完全相同。
- [ ] 运行 `flutter test test/editor/novel_editor_test.dart`，确认未实现功能失败；实现最小编辑验证程序，用 Flutter 编辑基础设施验证整体撤销、跨段选择、换行、只影响显示的首行缩进和段间距。
- [ ] 单独核实 Flutter 基础编辑组件的段落布局能力。不能用插入空格、覆盖原文、只改截图等方式模拟缩进。若需要自定义渲染或额外编辑依赖，先在验证报告写明输入法、选择、撤销和性能的结果及代价，取得技术取舍反馈后再扩展；本任务未通过不继续堆建工作台。
- [ ] 生成 10 万字单章与 300 万字全书样本；真实 macOS、Windows 分别验证中文候选输入、跨段撤销、按键到显示 p95≤100ms、切章≤1s。当前机器可先做 macOS，Windows 结果保持明确的未执行状态，不能以 macOS 结果代替。
- [ ] 通过单元测试、目标平台验证并记录机器、SDK、样本、测量方法；提交工程和验证记录，提交消息 `feat: establish desktop editor foundation`。Windows 的完整验证在任务 11 再执行一次，不要求跨平台构建在本机完成。

## Task 3 作品格式与字数

**Files:** 创建 `work_models.dart`、`work_codec.dart`、`note_models.dart`、`test/works/work_codec_test.dart`、`test/editor/word_count_test.dart`。

**Interfaces:** `WorkManifest`、`ChapterRecord`、`NoteRecord` 为不可变值；`NoteKind { outline, character, inspiration }`；`WorkCodec.decodeManifest(List<int> bytes) -> WorkManifest`；`encodeManifest(WorkManifest) -> List<int>`；`countWords(String text) -> int`。ChapterRecord 含 id、title、deletedAt；NoteRecord 含 id、kind、title、body、parentId、order、chapterId、deletedAt。角色姓名使用 title，简介用可空 summary。

- [ ] 写 `manifest_round_trip_preserves_order`、`rejects_duplicate_or_unsafe_ids`、`unknown_version_is_not_rewritten`；断言重复 ID、路径片段 ID、缺失必要字段拒绝加载并保留原始文件。写字数断言：`countWords('你 好\n，👨‍👩‍👧‍👦') == 4`、组合字形计 1、回收站不入全书总数。
- [ ] 运行 `flutter test test/works/work_codec_test.dart test/editor/word_count_test.dart`，确认失败。
- [ ] 实现上述值类型、显式 JSON 序列化和字素簇统计；统一文本内部换行为 `\n`，新作品生成安全 ID，避免依赖代码生成。
- [ ] 重跑测试通过后提交 `feat: define portable work records and word counts`。

## Task 4 文件保存与冲突保护

**Files:** 创建 `local_file_store.dart`、`record_store.dart`、`operation_journal.dart`、`work_repository.dart`、`test/storage/record_store_test.dart`、`test/storage/operation_journal_test.dart`、`test/works/work_repository_test.dart`。

**Interfaces:** `LocalFileStore` 封装 readBytes、writeBytes、replace、exists、list、delete；允许测试替身在指定写入步骤抛出文件异常。`RecordVersion` 封装内容 SHA-256；`RecordStore.read(String relativePath) -> Future<VersionedBytes>`；`write(String relativePath, List<int> bytes, {required RecordVersion? expected}) -> Future<SaveOutcome>`，SaveOutcome 为 Saved、Conflict、Failed；expected 为 null 时只允许新建。`WorkRepository.create(Directory root, String title)`、`open(Directory root)` 返回 `Future<WorkHandle>`；WorkHandle 暴露 manifest、readChapter、saveChapter、createChapter、renameChapter、reorderChapters、watchChanges、close。

- [ ] 写断言：外部内容已变则保存返回 Conflict，两个版本字节均保留；时间戳变化而字节相同不报冲突；注入临时写入、替换失败后原稿仍可读取；每记录写入串行，旧保存完成不能覆盖更晚保存。
- [ ] 为新建、重命名、章节重排写中断恢复测试，在每个持久化步骤后模拟终止；重新打开时按操作日志恢复到可读一致状态，不用空清单兜底。操作日志包含 ID、受影响路径、前后版本及待提交内容；重放可重复执行，冲突先保留。
- [ ] 运行 `flutter test test/storage/record_store_test.dart test/storage/operation_journal_test.dart test/works/work_repository_test.dart`，确认失败。
- [ ] 实现同目录临时写入、flush、平台替换及操作日志；在两平台实测目标已存在时的替换语义，失败不通过先删目标文件来冒充原子替换。必要的原生替换封装放在 desktop_services.dart 的平台实现中。
- [ ] watchChanges 使用文件监听作为触发，窗口回到前台与每次保存前再次比较版本；识别已知记录对应的网盘冲突副本并提示保留。多机竞态不能承诺强一致；检测到的冲突不自动选时间较新的文件。
- [ ] 测试通过后提交 `feat: persist works with recoverable writes and conflict protection`。

## Task 5 本地历史 目录访问与设备恢复

**Files:** 创建 `history_store.dart`、`recovery_store.dart`、`desktop_services.dart`、`instance_coordinator.dart`、偏好两个源文件、`macos/Runner/DirectoryAccess.swift`；修改 AppDelegate、DebugProfile.entitlements、Release.entitlements；创建 `test/storage/history_store_test.dart`、`test/platform/instance_coordinator_test.dart`、`test/preferences/preferences_store_test.dart`。

**Interfaces:** `HistoryStore.capture(String workKey, String recordId, List<int> bytes, DateTime now)`、`list(String workKey, String recordId)`、`restore(String snapshotId)` 返回 Future；restore 必须先快照当前值，再走版本化保存。`DesktopServices.pickWorkDirectory() -> Future<Directory?>`、`restoreDirectoryAccess(String token) -> Future<Directory?>`、`focusWindow()`、`requestClose()`；`InstanceCoordinator.acquire(String canonicalPath) -> Future<InstanceLease>`；`PreferencesStore.load() -> Future<DevicePreferences>`、`save(DevicePreferences)`；`RecoveryStore.writeSession(String workKey, SessionRecovery record)`、`readSession(String workKey)`。

- [ ] 写 `keeps_latest_100_distinct_snapshots`：第 101 个不同快照后保留 100 个，未处理冲突仍在；无变化不增长。写 `restore_keeps_current_version`、`missing_directory_keeps_recent_entry`、`corrupt_preferences_preserve_copy_and_use_defaults`。
- [ ] 写同机双进程测试：以规范路径和大小写别名打开同一目录，第二进程发起激活而非拿到编辑权；强杀首进程后锁可重新获取。macOS 符号链接、Windows junction 与大小写由平台规范化处理并实测。
- [ ] 运行 `flutter test test/storage/history_store_test.dart test/platform/instance_coordinator_test.dart test/preferences/preferences_store_test.dart`，确认失败。
- [ ] 本地历史置于 applicationSupportDirectory，以规范路径+workId 的摘要为 workKey；生成快照频率 5 分钟，恢复前与关闭前捕获不同内容。恢复记录保存已确认正文及原文 UTF-16 selection offset；重启时夹取到有效边界，不跨章节套用。
- [ ] 编辑锁文件放本机数据目录，持有 OS 文件锁直到关闭；锁元数据含进程、loopback 端口和随机 token，只转发本机打开请求。使用 window_manager 激活首实例；支持本机 loopback 所需的 macOS 权限，避免把锁文件放进同步目录。
- [ ] file_selector 选择目录；macOS 在两份 entitlements 添加用户选择文件读写与 app-scope bookmark 权限，通过 DirectoryAccess 创建/解析 security-scoped bookmark，保持访问作用域至关闭作品，失效则要求重新定位。用真实 release 构建重启验证授权，不以开发版访问成功代替。
- [ ] 保存失败不得丢当前会话；恢复记录写入本机时也可能失败，显示真实状态。测试通过后提交 `feat: add local history directory access and session recovery`。

## Task 6 编辑会话与自动保存

**Files:** 完成 `editor_session.dart`、`novel_editor.dart`、`paragraph_layout.dart`；创建 `test/editor/editor_session_test.dart`、`test/editor/autosave_test.dart`。

**Interfaces:** `EditorSession extends ChangeNotifier` 持有稳定编辑控制器、撤销与滚动状态；`open(WorkHandle work, String chapterId) -> Future<void>`、`flush() -> Future<SaveOutcome>`、`close() -> Future<SaveOutcome>`、`updateLayout(EditorLayoutSettings layout)`；状态为 clean、dirty、saving、conflict、failed。`SessionRecovery` 含 chapterId、text、selection、scrollOffset、baseVersion；异步结果以 session generation 与内容版本匹配后更新。

- [ ] 使用 fake_async 写 `saves_after_1s_idle`、`continuous_input_saves_by_10s`、`old_completion_does_not_mark_new_text_clean`、`failed_close_preserves_buffer`；输入法组合期间计时与换肤均不改 composing。写切章失败时仍保留原会话、用户可另存后离开的测试。
- [ ] 运行 `flutter test test/editor` 确认新增用例失败；实现单记录串行保存、去重与版本结果判断，切章/切作品/退出先 flush，失败保留内容并提示处理。
- [ ] 接入当前章节字数与全书缓存，后台只更新变化章节；统计结果带内容版本，旧统计不覆盖新文本结果。资料在任务 8 复用保存调度规则，不复用正文编辑控制器。
- [ ] 通过任务 2 的输入与排版测试，保证还原恢复记录时不写入空白缩进；测试通过后提交 `feat: add resilient editor sessions and autosave`。

## Task 7 主题与设备排版

**Files:** 创建 appearance 目录五个源文件；扩展偏好文件；创建 `test/appearance/appearance_controller_test.dart`、`test/appearance/appearance_widget_test.dart`。

**Interfaces:** `AppearanceSettings` 含 presetId、wallpaperPath、accentColor、editorOpacity、backgroundDim、backgroundBlur、animationsEnabled；`AppearanceController extends ChangeNotifier` 暴露 settings、`update(AppearanceSettings)`、`resetCurrentPreset()`、`importWallpaper(File file)`；`DevicePreferences` 分开存 appearance 与 EditorLayoutSettings。颜色映射通过 Flutter ThemeExtension 提供。

- [ ] 写 `changing_theme_preserves_layout_and_session`、`reset_only_resets_current_preset_overrides`；更新外观后正文、selection、composing、scrollOffset 均相同。写损坏壁纸与原文件被移动后仍能显示已导入本地副本的测试。
- [ ] 运行 `flutter test test/appearance` 确认失败；按照任务 1 图稿实现温暖/低亮度两套主题、即时预览和恢复默认。透明度范围 0.7–1，背景压暗 0–0.7，背景模糊 0–16；参数变动不重建编辑会话。
- [ ] 外观切换过渡 160ms，系统减少动效或用户关闭时为 0；壁纸缩放与解码按显示尺寸缓存，只模糊背景层。读取失败显示主题底色并给出重新选择入口。
- [ ] 排版控件更新 EditorLayoutSettings 并单独落盘；字体列出平台可用字体，不运行时联网下载。字体不可用时使用平台中文回退。
- [ ] 以 1280×800 和 1440×900、两种系统缩放检查正常、悬停、键盘焦点和选择状态；测试通过后提交 `feat: implement warm themes and personal appearance settings`。

## Task 8 工作台与创作资料

**Files:** 创建 workbench、library、notes、recovery 中所列界面与控制器；扩展 work_repository.dart；创建 `test/workbench/workbench_test.dart`、`test/notes/notes_controller_test.dart`、`test/recovery/recovery_test.dart`。

**Interfaces:** WorkHandle 增加 `saveNote(NoteRecord note, {required RecordVersion? expected})`、`trash(String recordId)`、`restore(String recordId)`、`purge(String recordId)`；`NotesController` 暴露大纲树、角色、灵感，`moveOutline(String id, String? parentId, int index)`、`linkInspiration(String id, String? chapterId)`；`WorkbenchController` 持有 work、session、notes 与 LayoutState，提供 `selectChapter`、`setPanel`、`toggleFocus`、`openLibrary`。

- [ ] 写 `focus_restores_sidebar_state`、`launch_resumes_last_chapter`、`external_change_opens_conflict_without_overwrite`；资料侧栏切换不改变正文控制器。写大纲不能形成环、角色可选字段为空、灵感无关联章节可保存的用例。
- [ ] 写 `trash_chapter_keeps_inspiration`、`purge_chapter_unlinks_inspiration`、`restore_keeps_current_snapshot`；父大纲回收包含子树，恢复整棵子树，永久删除前显示受影响条目；回收操作不计入全书字数。
- [ ] 运行 `flutter test test/workbench test/notes test/recovery` 确认失败；实现图稿中的工作台、章节操作、新建/打开书架、右侧三类资料、专注模式、历史/回收站与冲突比较。冲突选择以当前版本重新校验，外部再次变化就继续保留新版本。
- [ ] 章节重排、资料层级操作、回收和永久删除全部经 WorkHandle 与操作日志写入。保存状态文案固定为“待保存 / 正在保存 / 已保存到本机 / 保存失败 / 发现冲突”。
- [ ] 当没有可恢复章节时打开该作品目录页；目录不可访问时保留最近记录，显示重新定位、打开其他作品入口，不创建空作品覆盖。
- [ ] 测试通过并按图稿检查后提交 `feat: assemble writing workbench and lightweight novel notes`。

## Task 9 TXT 与完整作品备份

**Files:** 创建 text_transfer.dart、backup_service.dart、transfer_dialogs.dart；创建 `test/transfer/text_transfer_test.dart`、`test/transfer/backup_service_test.dart`。

**Interfaces:** `TextTransfer.decode(List<int> bytes, {String encoding = 'utf-8'}) -> String`、`importChapter(WorkHandle work, String title, String text)`、`exportChapter(WorkHandle work, String id)`、`exportWork(WorkHandle work)` 返回 Future；`BackupService.create(WorkHandle work, File destination)`、`restore(File source, Directory parent) -> Future<WorkHandle>`。

- [ ] 写 UTF-8/BOM、CRLF、GB18030 四字节字符、截断字节测试，错误编码抛错供用户选择，禁止 replacement character 静默替换。写整书导出顺序、标题、空行、无删除内容及无显示缩进字符的测试。
- [ ] 写备份往返测试：正文、回收站、层级、顺序、关联一致；恢复生成独立 workId；归档中含 `../`、绝对路径、重复记录、未知格式或缺记录时不写入目标，临时目录清理且保留来源文件。
- [ ] 运行 `flutter test test/transfer` 确认失败；使用严格 charset_codec GB18030 解码并以已知字节样本验证四字节映射，UTF-8 导出。完整备份使用 ZIP，附格式版本和各文件摘要，读取时先验证后在新目录恢复。
- [ ] 导出前 flush 当前会话，失败先处理；完整备份读取版本清单前后保持一致，检测到外部变化则重试或提示，不生成看似成功的混合版本。打包排除临时文件、设备偏好、独立历史与锁。
- [ ] 跨平台导入同一备份并检查中文名称、换行、角色和删除状态；测试通过后提交 `feat: add txt transfer and portable work backups`。

## Task 10 桌面操作与退出流程

**Files:** 修改 desktop_services.dart、inkflow_app.dart、工作台界面、macos/Runner/AppDelegate.swift；创建 `test/platform/desktop_actions_test.dart`、`integration_test/desktop_workflow_test.dart`。

**Interfaces:** `DesktopActions` 把平台快捷键映射为当前焦点作用域的 Intent；`requestClose()` 必须等待 EditorSession.flush 和恢复位置保存，再关闭窗口；失败返回工作台并保留另存入口。

- [ ] 写 `shortcuts_target_focused_editor`、`close_waits_for_save`、`save_failure_cancels_close`；确认资料中复制/撤销不会作用于正文，Esc 退出专注模式，Tab 可访问主要按钮。
- [ ] 运行 `flutter test test/platform/desktop_actions_test.dart` 确认失败；使用 Actions/Shortcuts 和 macOS 原生菜单，Windows Ctrl、macOS Cmd 处理保存/导入/导出/撤销等常用操作；关闭窗口、菜单退出与系统退出走统一待保存处理。
- [ ] `flutter test integration_test/desktop_workflow_test.dart -d macos` 验证新建作品→编辑→查资料→换肤→导出→退出→重启；Windows 主机使用同一命令的 `-d windows`。
- [ ] 通过后提交 `feat: finish desktop menus shortcuts and safe shutdown`。

## Task 11 双平台验收与交付

**Files:** 创建 `docs/verification/desktop-acceptance.md`、`integration_test/recovery_scenarios_test.dart`、`integration_test/editor_performance_test.dart`、`tool/verify_work_directory.dart`；修正上述任务中被证据定位的问题。

**Interfaces:** 接受 work.json 格式 1 的只读校验工具；输出记录来源、样本摘要、机器、OS、SDK、构建模式、结果和失败证据的验收记录。

- [ ] 固定并记录 Windows 与 macOS 各一台验收机器，不临时删减 10 万字单章、300 万字全书样本；profile 构建测量 200 次普通输入的按键到渲染延迟与 20 次切章，分别报告 p95 与最大切章耗时，输入法测试另外手工执行。
- [ ] 运行 `dart format --output=none --set-exit-if-changed lib test integration_test tool`、`flutter analyze`、`flutter test`；预期格式返回 0、分析无问题、测试全部通过。
- [ ] macOS 运行 `flutter build macos --release`，Windows 主机运行 `flutter build windows --release`；分别运行集成测试、实际 IME 输入与 release 重启目录授权。任一平台不可用时记录未执行，并保持双平台验收未完成。
- [ ] 故障演练：写入步骤中终止进程、断开作品目录、保存失败后另存、同机双开、外部正文/清单修改、历史恢复、备份还原。断言来源与本地新内容都能定位，缺文件不触发空内容覆盖。
- [ ] 检查两套主题、外观预览、关闭动效、系统缩放、所有面板、正文排版与导出一致；按设计文档第 9 节逐行关联自动测试或人工证据。修复后重跑受影响检查。
- [ ] 提交 `test: verify desktop writing and recovery acceptance`。交付本地可运行应用、构建产物路径和验收记录；对外签名、公证和发布单独安排，不把本地构建标为已发布。

## 技术依据与执行注意

- Flutter 基础编辑控制器的 text 赋值会清除选择和 composing；保存与主题更新不回写控制器：[TextEditingController](https://api.flutter.dev/flutter/widgets/TextEditingController-class.html)。
- 桌面文件选择支持目录和保存位置，macOS 需要配置用户选择读写权限：[file_selector](https://pub.dev/packages/file_selector)。重启持久授权在任务 5 用平台 bookmark 处理。
- 窗口生命周期选择现有 SDK 可尝试的 0.5.1 分支：[window_manager 0.5.1](https://pub.dev/packages/window_manager/versions/0.5.1)。当前 0.6.0 要求 Flutter 3.47 / Dart 3.13，不在本计划中升级 SDK：[0.6.0 requirements](https://pub.dev/packages/window_manager)。
- GB18030 使用明确支持该编码及严格错误模式的依赖，执行时必须验证四字节字符与截断字节：[charset_codec](https://pub.dev/packages/charset_codec)。
- 保留 macOS DebugProfile 的原有开发权限，同时对两份 entitlements 同步必要权限：[Flutter macOS 平台说明](https://docs.flutter.dev/platform-integration/macos/building)。

当前目录尚未初始化 Git，当前主机为 macOS。计划编写阶段仅创建文档，未生成应用、安装依赖或执行产品测试；Windows 运行与验收需要 Windows 主机。执行阶段先建立本地版本记录，再按所选执行方式处理隔离工作区，不为文档阶段创建空 worktree。

## 计划自检

- 产品定位、平台与默认启动：任务 1、2、8、10。
- 小说纯文本与排版、字数、长篇性能：任务 2、3、6、11。
- 创作资料、关联、回收站：任务 3、8。
- 两主题、自定义、设备偏好和动效：任务 1、5、7。
- 文件同步边界、保存失败、冲突、操作恢复：任务 4、5、6、8、11。
- TXT、完整备份与跨平台迁移：任务 9、11。
- 所有任务先验证对应行为；视觉图稿和生成脚手架不编写镜像测试；数据、编辑和恢复功能先失败用例再实现。
