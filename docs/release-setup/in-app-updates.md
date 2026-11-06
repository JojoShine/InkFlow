# 应用内更新发行说明（0.1.6 起）

InkFlow 使用现有 Sparkle（macOS）及 WinSparkle（Windows）完成下载、安装和重新启动。安装前先保存稿件；保存失败时不允许安装。

更新包签名与平台开发者证书分开配置：

- macOS 更新包使用 Ed25519；必须通过打包时的公钥验证。
- Windows 当前 WinSparkle 版本使用 DSA；必须通过安装器签名验证。
- Apple Developer ID 签名、公证及 Windows Authenticode 证书均按发行条件选配。缺少平台证书时仍要求有效更新包签名，不能宣称已公证或已取得受信任的发布者签名。
- 缺少更新签名或校验失败时，发布必须停止，不写入更新订阅。

仓库 Secrets 使用 `MACOS_ED25519_PRIVATE_KEY`、`MACOS_ED25519_PUBLIC_KEY`、`WINDOWS_DSA_PRIVATE_KEY`、`WINDOWS_DSA_PUBLIC_KEY`，仓库变量 `INKFLOW_SIGNED_UPDATES=true` 启用签名更新。私钥独立于 Lockora，存入 GitHub Secrets，不进入源码、安装包、OSS 或日志。私钥丢失后不能任意更换公钥，应备份并沿用。

Apple 签名、公证不是启用此流程的必填资料。此前发布清单中将其列为硬性前置条件的表述，以本说明为准。Sparkle 官方同样区分更新包签名与可选的 Developer ID 分发建议：<https://sparkle-project.org/documentation/>。

旧预览版没有内置更新公钥，需要手动安装 0.1.6 一次。此后通过应用内的检查更新窗口下载，确认后安装并重新打开。macOS 应将应用放在可写安装位置，不从压缩包临时预览位置运行。

发行继续使用匹配 `pubspec.yaml` 的 `vX.Y.Z` 标签触发 GitHub Actions。先构建并验证所有平台包，再上传不可变版本目录，更新订阅和历史清单，最后提交 `latest.json`。默认只发布桌面安装包和更新清单；仅明确传入 `--site-root` 时才同时上传网站文件。

验证要求：控制器必须优先使用已启用的原生更新器；无效签名和篡改包必须拒绝；Windows 静默安装必须重新打开应用；实际平台安装升级测试不能用静态检查代替。
