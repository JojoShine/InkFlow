# InkFlow 应用版本与 OSS 更新

## 用户确认

- macOS、Windows 应用内安装更新并重新启动，退出前必须保存稿件。
- 应用标识 `me.tbtparent.inkflow`；旧版 `dev.inkflow.inkflow` 数据须先授权复制迁移，不能直接丢弃。
- 下载源 `https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/`。
- 根 `index.html` 为公开宣发与下载入口；源码仓库 `JojoShine/InkFlow` 为私有。
- GitHub Actions 构建双端，并通过 OSS 管理不可变版本包、下载清单和原生更新 feed。

## 版本与更新协议

pubspec `X.Y.Z+build` 是版本唯一来源。tag `vX.Y.Z` 精确匹配展示版本；build 全局递增，不允许覆盖已经发布的版本。包路径、清单、缓存策略、Secrets、失败恢复流程见 [发布说明](../../releases.md)。

macOS arm64 / x64 使用各自 Sparkle Ed25519 feed；Windows x64 使用 WinSparkle DSA feed。正式发布校验更新签名，macOS 另要求 Developer ID 签名与 notarization。客户端根据实际打包公钥和架构开启更新，开发包不伪装成可用的正式更新版本。

## 保存与迁移

安装准备先提交输入法组合并原子锁定原生正文，再保存全部稿件、笔记和位置。保存失败、安装错误、取消和超时恢复编辑；迟到保存回调不可触发退出或再次上锁。Windows 配置 native can-shutdown gate，不能依赖安装器启动后的事件来防止数据丢失。

新 macOS 标识首次启动，在初始化最近作品之前展示新用户/旧数据导入入口。旧版必须先保存退出；系统文件夹授权后复制偏好、内部作品、历史、恢复副本和壁纸，重新映射内部路径与 workKey。旧 bookmark 不复用，外部书库重新授权。目标已有数据时拒绝覆盖，失败保留旧目录。

## 验证范围

自动化覆盖更新事件、保存门控、迁移字节保持及冲突拒绝、发布版本/散列/feed 验证。GitHub 三目标构建是交付检查的一部分；真实安装重启、Windows 输入法与首次正式签名更新仍需对应平台验收。未配置 Secrets 不进行 OSS 正式发布，不将“工作流已配置”描述成“已经发布上线”。
