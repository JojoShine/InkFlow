# 共享目录、Windows 体验与 AI 面板验证

日期：2026-11-06。平台：macOS 26.5 arm64，Flutter 3.41.9 / Dart 3.11.5。实现位于 `codex/desktop-ai-demand-loading` 隔离分支，基线为 `3714398`。原工作区已有的官网与发布改动未带入或修改。

## 已实现

- 工作台显式按需打开作品；清单先显示，目录信息最多四个并发、每批最多 32 条；正文只读取当前请求章节。笔记每批最多 16 份，并显示正在读取、已检查范围、慢读提示和继续加载入口。
- 取消使旧加载结果失效并移除排队元信息读取；系统已经开始的文件读取可能继续完成。切章、刷新与恢复均检查作品和章节身份。未知全书字数显示未统计，不再后台读遍所有正文。
- 全书导出和涉及关联的删除显式补齐所需记录，破坏性操作重新获取资料清单。共享目录缺失或未就绪文件不创建空白替代稿件。
- 历史捕获按记录串行化，复制入队字节，相同内容命中哈希缓存；保存后再退出，排空对话保存并释放单实例资源。保存失败恢复编辑。
- Windows 原生桥增加视口位图捕获；Flutter 先显示快照再隐藏 HWND，恢复 HWND 后释放快照，保留原编辑器实例。
- 灵感右侧增加 AI 页签，提供整理思路、评价内容、总结内容。配置 DeepSeek、Kimi、GLM、Qwen、OpenAI 或自定义 HTTPS Chat Completions 服务；模型 ID 可填写。
- 密钥仅经系统凭据通道读写；非密钥配置与每作品的一份当前对话保存在本机。附件主动选取、预览并发送；已发送的附件随当前对话的后续历史重发。发送内容上限为 96KiB UTF-8 文本。
- 流式处理中文/emoji、完成、中断、错误与停止；不自动重试。重试保留原模式和附件，并在新回复开始前保留旧的部分回复。

## 已运行的检查

| 检查 | 结果 |
| --- | --- |
| 基线 `flutter test --no-pub` | 200 通过，2 项原有跳过 |
| 按需加载首次完整回归 | 205 通过，2 项原有跳过 |
| 最终 `flutter test --no-pub` | **233 通过，2 项原有跳过，0 失败** |
| 最终 `flutter analyze` | **No issues found** |
| `flutter build macos --debug --no-pub` | **成功** |
| 260px AI 侧栏、页签入口、Enter 发送、快捷草稿和原稿不变 | 组件测试通过；使用临时样例 |
| 原生 macOS 凭据桥 | 随机命名的临时凭据写入、读取、更新、删除及删除后读取均通过 |
| 本地真实 HTTP 传输 | 请求 JSON 内容范围、SSE 中文回复和 401 响应脱敏通过；非真实模型服务 |
| 千章目录 | 1000 个章节 ID 的样例清单只读取 32 个请求的章节信息及当前章节正文，其余未下载内容不被读取 |
| 快照切换顺序 | Windows 通道模拟确认 snapshot 在 visible=false 前、恢复后 visible=true；不是 Windows 实机渲染验收 |

测试入口包括 `test/works/demand_loading_test.dart`、`test/workbench/demand_loading_test.dart`、`test/workbench/async_review_test.dart`、`test/works/partial_cache_review_test.dart`、`test/works/read_cancel_test.dart`、`test/workbench/note_loading_test.dart`、`test/ai/`、`test/editor/windows_overlay_transition_test.dart`、`test/storage/history_concurrency_test.dart` 和现有保存/更新安全测试。

## 历史捕获测量

运行：

```sh
dart --packages=.dart_tool/package_config.json tool/history_capture_benchmark.dart
```

本次 macOS 结果：100 份不同历史，每份正文 12003 字节；连续 20 次相同内容捕获，缓存命中总计 **4223μs**，强制使缓存失效并扫描总计 **267646μs**。最终仍有 100 份历史。

这是相同实现的“命中缓存 / 强制扫描”对照，说明取消重复扫描的效果；不是两个版本的 Windows 退出计时，不能据此宣称 Windows 已达到 500ms / 1s 目标。

## 原生凭据复现

先完成 macOS debug 构建，再运行：

```sh
swiftc -F build/macos/Build/Products/Debug \
  -framework FlutterMacOS -framework Cocoa -framework Security \
  macos/Runner/AiCredentials.swift tool/native_ai_credentials_probe.swift \
  -Xlinker -rpath -Xlinker "$PWD/build/macos/Build/Products/Debug" \
  -o /tmp/inkflow-credentials-probe
/tmp/inkflow-credentials-probe
```

探测程序经 Flutter 方法编解码调用实际的 `AiCredentials`，只操作随机 ID 对应的测试凭据，正常或抛错退出时清理；不读取已有凭据、不打印密钥。本次输出：`native credential write/read/update/delete passed`。

## 独立审查与修复

对 `3714398..c6342c3` 做了一次独立只读审查；以下问题均先复现失败，再修复并通过完整回归：

| 问题 | 修复与回归 |
| --- | --- |
| 延迟外部刷新 A 返回后重新选中 A，覆盖用户新选的 B | 绑定加载代次、章节和编辑会话；`late external refresh does not reselect an older chapter` |
| 延迟恢复记录发布到另一章，或接受恢复时串章 | 发布与应用前后检查作品/章节/正文；`late recovery read is never published into a different chapter` |
| 本机 AI 对话尚未读完时允许写入覆盖旧记录 | 对话加载作为不可写状态；`conversation load is not writable before existing history is installed` |
| 重试顺带发送未提交附件，或凭据失败后丢失部分回复 | 重试显式使用原附件、模式，验证后再替换轮次；`retry preserves explicit absence of attachment and retains failed partial reply if validation fails` |
| 笔记历史恢复把未加载章节误判为不存在 | 按 manifest 判断关联；`restoring a note preserves an unloaded but existing chapter link` |
| 资料目录缓存遗漏新到达笔记，导致删除关联不完整 | 刷新和完整操作重新枚举，彻底删除前更新资料内容；`purge refreshes a stale note inventory before removing chapter links` |
| 取消仍继续启动排队读取 | 队列失效，保留在途结果的代次保护；`invalidate drops queued cloud reads while active reads finish` |
| 旧凭据读取返回后清除新请求忙状态 | 清理只属于当前请求；`cancelled credential lookup cannot clear a newer send busy state` |

补充回归覆盖旧作品加载等待期的正文和笔记保存、取消后延迟错误失效、千章目录、跨作品附件拒绝、选区 emoji 和附件变化提示。AI 目标对话读取完成后才原子切换；取消时保留原对话。用户明确放弃失败的对话保存时仍取消当前网络请求。

## 实施决定

- 将耦合的接口与 UI 变更按可运行检查点提交：便于保持可验证版本，代价是单次提交审查范围较大。
- 使用受管理的隔离工作区及逐命令授权写入：保留原目录的未提交改动，代价是权限处理开销。
- 加载阶段采用文字与静态活动图标：反馈保持明确，代价是没有持续旋转动画。
- 保留既有 `NoteKind` 面板接口，通过独立 AI 选择状态和共享页签头扩展：作品格式与已有调用兼容，代价是控制器需保持两种选择状态一致。
- 浮层使用通用路由信号触发快照，未逐个弹窗预热：覆盖现有入口，代价是首次 HWND 交接帧仍需 Windows 视觉验证。
- 历史缓存消除了原排版竞态测试依赖的磁盘等待：测试中通过公开 invalidation 恢复真实历史 IO，代价是该测试依赖缓存失效契约。
- 本机历史文件视为应用管理的数据，不增加外部删除轮询来破坏快速路径：代价是在没有任何失败操作的情况下，外部手工删除历史文件未必立即被发现；公开历史读取/恢复会失效缓存。

低优先级暂缓：`AiTurn.fromJson` 会重建当前时间戳，已加载记录的创建时间元数据没有保留原值；当前界面不显示时间戳，不影响正文、对话内容或附件。

## 尚待真实环境验收

- **Windows**：原生编译、位图是否完整、100%/125%/150%/200% DPI、IME、主题/尺寸变化、焦点与撤销、凭据管理器，以及窗口消失和进程退出的独立计时。不能以 macOS 构建或通道模拟代替。
- **iCloud / 共享文件夹**：真实占位文件、离线、恢复联网、外部同步/删除和系统自动下载行为。当前验证是临时目录、缺失文件和受控延迟；应用主动读取数与系统同步行为必须分开记录。
- **五家模型服务**：需要测试者提供有效 API Key，逐家验证真实文本、流式、停止、权限和模型参数。当前只完成协议与模拟/本地服务测试，未使用私人密钥或产生真实模型调用。
- Windows 退出目标尚无实测结论：同机同构建下，对无作品、未编辑、刚编辑、100 条笔记 × 100 份历史及十万字章节各至少运行 10 次，分别记录中位数、最慢值、窗口和进程结束时间。

代码和已验证的变更可以评审；以上平台/账号验证仍保留为未完成的验收项目。
