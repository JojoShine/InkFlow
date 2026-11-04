# 当前预览下载（2026-11-05）

宣发页位于 `https://tbtparent.me/inkflow/`，使用服务器已有 tbtparent.me HTTPS 站点下的独立路径，参照 Lockora 的部署方式；没有 IP 独立站点。

0.1.0+1 的两个安装包已放在 `https://tbtparent.me/inkflow/downloads/0.1.0%2B1/`：

- `InkFlow-0.1.0+1-windows-x64.exe` 来自 Actions run `41861876491` 的 `desktop-windows-x64` 工件（artifact `13341631649`）。Windows 构建、原生编码测试与 Inno Setup 打包日志均成功，包与工件 sidecar 的 SHA256/长度一致。
- `InkFlow-0.1.0+1-macos-universal.zip` 来自本机已通过的 Flutter release 构建。主程序与 App.framework 都经 lipo 验证包含 x86_64 / arm64；这不是 GitHub Mac 构建通过的证明。

两个安装包均经过公网完整下载及 SHA256 校验。当前没有开发者签名证书与更新签名配置，因此只发布为 **预览版**，页面明确显示说明，不生成或发布无签名的自动更新 feed。

当前服务器目录：

- 静态页面：`/srv/www/inkflow/current/`（指向独立的静态版本目录）。
- 安装包：`/srv/www/inkflow/downloads/0.1.0+1/`（已发布后不可覆盖）。
- 静态版本中的 `downloads` 软链接指向上述共享下载目录；后续替换静态版本时要保留该链接。
- `latest.json` / `releases.json` 是暂存在服务器的预览清单，安装包全部上传并校验后才写入。

官网只允许预设 OSS HTTPS 下载前缀和 `https://tbtparent.me/inkflow/downloads/`，不接受任意域名、HTTP、路径穿越或不匹配的平台类型。

正式 OSS 签名发布配置见 [发布文档](releases.md)。转为正式 OSS 发布时，需要同步替换服务器上的两个临时预览清单，或移除它们并确保 OSS JSON 允许官网跨域读取；不能让同源旧预览清单遮住新版本。GitHub 中两个 Mac 作业的结果必须另行确认，不能把本机打包或已配置工作流描述成 Mac CI 已通过。
