# InkFlow

一间轻量、愉悦、属于小说作者的桌面书房。使用 Flutter 构建，支持 macOS 与 Windows。

- 作品书架、封面与简介，卷和章节管理。
- 正文写作、专注模式、排版预览、码字统计与键音。
- 人物、大纲、灵感笔记；多种书房与背景主题。
- 本地保存、历史记录、TXT 导出、完整备份与分享卡片。
- 带签名校验和保存保护的桌面更新接入；正式启用需要发布密钥配置。

## 共享目录与 AI 讨论

大作品按需读取章节和资料，加载期间显示阶段、等待提示及重试入口；未知全书字数标为未统计。目录中的未下载文件保持原状，全文导出和涉及关联的删除会显式补齐所需内容。

“灵感”右侧的 AI 页签用于整理思路、评价和总结。选择服务商，填写 HTTPS Base URL、兼容 Chat Completions 的文本模型 ID 和自己的 API Key，再保存配置。密钥由 Windows 凭据管理器或 macOS 钥匙串保存；“测试连接”会发送一条固定短消息，可能产生模型调用费用。

对话默认使用输入内容和当前对话历史；选中文字或当前章节可先预览再附加。每部作品在本机保存一份当前对话，更换连接或开启新对话前会确认。回复可选择、复制，正文保留原有编辑与撤销流程。

本轮验证结果及真实环境待验收项见 [桌面体验验证记录](docs/verification/2026-11-06-desktop-experience.md)。

## 开发

需要 Flutter 3.41.9（Dart 3.11.5）。macOS 使用 Xcode 和 CocoaPods；Windows 使用 Visual Studio Desktop development with C++。

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d macos
```

应用标识为 `me.tbtparent.inkflow`。旧 macOS 版本的用户首次启动可选择导入旧版数据；外部书库需要重新授权，旧数据保留。

## 宣发页

根目录 `index.html` 与 `website/` 为无需构建的静态站。可在项目目录运行 `python3 -m http.server 8787` 预览。
网站从同源 `latest.json` / `releases.json` 读取版本，回退至已配置的 OSS HTTPS 源。没有已发布清单时，下载区明确显示尚未发布。

## 构建与发布

GitHub Actions 在 push / PR 构建 macOS Apple Silicon、macOS Intel、Windows x64 完整工件。与 `pubspec.yaml` 一致的 `vX.Y.Z` tag 触发正式发布；签名验证和 OSS 凭据齐备后，才会上传安装包、版本清单、更新 feed 与宣发页。

配置方法、Secrets 清单、首次发布与恢复说明见 [发布文档](docs/releases.md)。

不将作品、个人书库、私钥或上传凭据提交到版本库。

当前公开预览：[tbtparent.me/inkflow/](https://tbtparent.me/inkflow/)。两端预览下载的来源、验证记录和临时分发方式见 [预览下载说明](docs/preview-downloads.md)。
