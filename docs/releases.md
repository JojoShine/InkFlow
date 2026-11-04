# InkFlow 桌面构建与 OSS 发布

发布源为私有仓库 [JojoShine/InkFlow](https://github.com/JojoShine/InkFlow)。下载与更新走公开 HTTPS OSS：
`https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/`。
仓库和 GitHub 工件可保持私有；OSS 的该下载前缀必须允许匿名读取，禁止匿名写入。不要公开 bucket 的其它业务对象。

## 常规构建

`.github/workflows/desktop.yml` 在 push、PR、手工运行时执行 Flutter analyze、Flutter test、发布工具单元测试，并构建：

| 平台 | Runner | 工件 |
| --- | --- | --- |
| macOS Apple Silicon / Intel | `macos-26-intel`，构建通用二进制 | 两种架构各自的完整 `.app` ZIP |
| Windows | `windows-2022` (x64) | Inno Setup 安装 EXE |

Flutter 固定 `3.41.9`，自带 Dart `3.11.5`；依赖使用已提交 lockfile。mac 包保留 framework、XPC/helper、资源与符号链接；通用打包先验证主程序、App.framework 和 FlutterMacOS.framework 均含 x86_64 / arm64，再生成两份架构 feed 对应的包。Windows 安装器递归包含完整 Release 目录、Flutter engine、插件 DLL、assets，并添加 Visual Studio 已安装的 x64 VC CRT app-local DLL，不分发孤立 EXE。Windows runner 必须预装 Inno Setup 6 与 Visual C++ redistributable，缺失时明确报错。

普通构建无签名 secrets 时仍生成 CI 工件；这些工件不代表可公开分发或可自动更新。GitHub Actions 私有仓库构建会使用账户的 Actions 分钟配额。

## 发布前配置

用户需要提供的资料与首次可生成的更新密钥见 [一次配置清单](release-setup/checklist.md)，限定 OSS 权限见 [RAM policy](release-setup/oss-upload-policy.json)。

所有敏感值只使用 GitHub Actions Secrets（Settings → Secrets and variables → Actions）。建立 `release` environment，推荐为生产 OSS secrets 配置 environment protection。构建时使用的签名 secrets 必须是 **repository secrets**，因为 build job 不在 release environment 内；OSS secrets 可放 release environment。

| Secret | 用途与要求 |
| --- | --- |
| `MACOS_ED25519_PRIVATE_KEY` | **正式发布必需**。Sparkle `generate_keys -x <file>` 导出的私钥文件原文，保留原始格式；不会自动生成或轮换。 |
| `MACOS_ED25519_PUBLIC_KEY` | **正式发布必需**。Sparkle 输出的 base64 公钥，构建前注入 Info.plist `SUPublicEDKey`。发布签名会用打包 app 内的此公钥实际验证，公私钥不匹配会失败。 |
| `WINDOWS_DSA_PRIVATE_KEY` | **正式发布必需**。auto_updater 1.0.0 / WinSparkle 0.8.1 生成的 `dsa_priv.pem` 完整 PEM 内容。 |
| `WINDOWS_DSA_PUBLIC_KEY` | 可选，用于普通构建的公钥；tag 构建从私钥派生公钥并覆盖此值。公钥临时文件通过 `windows/runner/update_public_key.rc` 的 `DSAPub DSAPEM` 资源编入 EXE，CMake 必须条件包含该文件。 |
| `MACOS_CERTIFICATE_P12` | **正式发布必需**。Developer ID Application 签名证书与私钥的 `.p12` 文件，base64 编码。 |
| `MACOS_CERTIFICATE_PASSWORD` | **正式发布必需**。上述 p12 导出密码。 |
| `MACOS_SIGN_IDENTITY` | **正式发布必需**，完整 `Developer ID Application: … (TEAMID)` identity。 |
| `APPLE_ID` | **正式发布必需**，用于 notarytool 的 Apple ID。 |
| `APPLE_APP_PASSWORD` | **正式发布必需**，该 Apple ID 的 app-specific password。 |
| `APPLE_TEAM_ID` | **正式发布必需**，Apple Developer Team ID。 |
| `WINDOWS_CERTIFICATE_PFX` | 可选，Authenticode 证书 `.pfx` 的 base64。配置后必须签名成功；当前签安装器本体。 |
| `WINDOWS_CERTIFICATE_PASSWORD` | 使用 PFX 时必需。 |
| `OSS_ACCESS_KEY_ID` / `OSS_ACCESS_KEY_SECRET` | **正式发布必需**，建议专用 RAM 身份，只允许目标下载前缀的 GetObject / PutObject / DeleteObject 及列举（限制 ListObjects prefix）。DeleteObject 只需 `.release.lock`。 |
| `OSS_SECURITY_TOKEN` | 使用临时 STS credentials 时配置；长期 RAM key 可省略。 |

不要把私钥、p12/pfx、AccessKey、密码提交到 Git。公钥可公开，但本流程通过 secrets 注入以便管理；已安装客户端必须始终保留与发布私钥对应的公钥。丢失或随意轮换更新密钥会切断已安装版本的更新链。

macOS 发布要求 Developer ID、hardened runtime、notarization、stapling 和 Gatekeeper 验证全部成功；这是本项目对官网公开分发的要求。普通 CI 可省略。Windows DSA 更新签名为必需，Authenticode 可选但推荐（不签可能出现 SmartScreen 提示）。两种签名用途不同，Authenticode 不能代替更新签名。

macOS 沙盒集成需要 Sparkle installer launcher 配置、mach-lookup exception 及正确 helper entitlements；本项目已启用 network.client，因此按官方指南不启用单独 downloader service。参见 [Sparkle 沙盒指南](https://sparkle-project.org/documentation/sandboxing/)。客户端必须先正确集成 `auto_updater`、公钥与安全退出/安装流程，再宣称自动更新可用。本发布脚本不替代实机更新测试。

## 发布步骤

1. 修改 `pubspec.yaml` 为例如 `0.1.0+1`，并更新 `tool/release/notes.txt`（每个非空行是一条发布说明）。版本号使用三段稳定版本，不支持 prerelease。build 取 pubspec，禁止 Actions 自增或覆盖。
2. 提交变更，确认普通 CI 双端通过，再打 `v0.1.0` tag 并 push。tag 必须与 pubspec 的 `0.1.0` 精确相符，build 号必须大于 OSS **所有历史发布**，语义版本不能下降。相同语义版本的补包也须提高 build。
3. 三个目标全部构建并完成签名后，publish job 下载工件，重新核验文件名、目标、版本、build、长度、SHA256、签名验证状态与 mac notarization 状态。缺包、未签名、字节改变、缺 secrets 都会拒绝公开发布。
4. SDK 获取 OSS 独占 `.release.lock`，核对已有 latest/history，上传不可变版本目录，再上传静态站与 feed/history，最后写 `latest.json`。成功后自动释放 lock。整个发布不会创建 GitHub public release。

初始版本使用 `v0.1.0` + build `1`。由于当前尚未配置 secrets，tag 构建能产出工件，正式 OSS 发布会明确失败，**不会发布无签名 feed**。本次配置不包含实际 OSS 上传。

## 对象与协议

```text
Download/inkflow/
  index.html
  website/**
  latest.json
  releases.json
  appcast-macos-arm64.xml
  appcast-macos-x64.xml
  appcast-windows-x64.xml
  releases/0.1.0+1/
    InkFlow-0.1.0+1-macos-arm64.zip
    InkFlow-0.1.0+1-macos-x64.zip
    InkFlow-0.1.0+1-windows-x64.exe
    release.json
    appcast-*.xml
```

`latest.json` 是单条 release 对象，`releases.json` 为 `{ "releases": [最新, ...历史] }`。单条结构固定：

```json
{
  "version": "0.1.0",
  "build": 1,
  "publishedAt": "2026-11-04T00:00:00Z",
  "notes": ["发布说明"],
  "downloads": [
    {
      "platform": "macos",
      "arch": "arm64",
      "url": "https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/releases/0.1.0%2B1/InkFlow-0.1.0%2B1-macos-arm64.zip",
      "size": 123456,
      "sha256": "64位小写十六进制SHA256"
    }
  ]
}
```

正式清单包含三个目标；JSON 的 `build`/`size` 是数字，`publishedAt` 是 UTC ISO8601。URL 对 `+` 百分号编码，对象实际名称保留 `+`。

mac Sparkle feed 的 `sparkle:version` = build，`shortVersionString` = 展示版本，`edSignature` = Ed25519 签名。Windows 原生初始化必须调用 `win_sparkle_set_app_build_version` 传入 `FLUTTER_VERSION_BUILD`（在 plugin 的 `win_sparkle_init` 之前），以免把数字 build 与展示版本比较、反复提示更新。Windows 使用 WinSparkle 0.8.1 实际 `sign_update.bat` 算法（先 SHA1 文件，再对该摘要执行 DSA/SHA1），写 `dsaSignature`，不误用 EdDSA。`length` 总是实际安装包大小，修正 auto_updater Windows CLI 的 `length="0"` 输出。签名针对最后的归档/安装器字节；mac notarization/stapling 和 Windows 可选 Authenticode 均在更新签名前完成。

Windows feed 指定 `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-`。安装目录固定为当前用户的 LocalAppData，升级保持 AppId 与目录，自动关闭应用；安装器不在 silent 模式自动启动第二实例。不把用户写作数据放在安装目录内。

版本目录使用 `x-oss-forbid-overwrite=true`，缓存 `public, max-age=31536000, immutable`，永不原地覆盖。所有稳定清单、feed 与站点文件使用 `no-cache, no-store, must-revalidate`。网站只上传根 `index.html` 与 `website/**`，不会把仓库、源码或 secrets 上传。OSS SDK 默认传输 CRC 校验；清单另外记录本地最终文件 SHA256。

OSS 不支持跨对象事务。所有安装包均上传完并核对长度之后才写任何稳定入口，因此 stable feed 不会指向尚未上传的包；三个 feed/history/latest 之间仍可能短暂处在不同版本。`latest.json` 是网站发布的最后提交点。若中途失败，旧入口可能与新入口并存；不能声称完全原子切换。

GitHub `oss-production-release` concurrency 加 OSS exclusive lock 防止并发写。任务取消可能留下 `.release.lock`；确认没有运行中的 publisher 后，管理员才可删除。失败的不可变版本目录保留取证；不要自动覆盖或清理。若包阶段失败且稳定入口完全未变，可人工核对后删除该未发布目录并重跑；如果任一入口已更新，应先修复一致性并提高 build 做新发布。不得删除已经被用户下载的正式包。不要通过把 latest 指向更低 build 来“回滚”；发布更高 build 的修复版本。

## 本地验证与预览

```sh
python3 -m unittest discover -s tool/release -v
python3 -m pip install -r tool/release/requirements.txt
python3 tool/release/release.py --tag v0.1.0 --artifacts dist
```

默认只生成 `release-preview/` 清单，不联网、不上传。只有显式添加 `--publish` 才写 OSS，且仍执行所有验证。不在本地随意运行 `configure_keys.py`：它会修改原生公共密钥配置，设计用于一次性的 Actions checkout。

参考：[GitHub runner 类型](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)、[auto_updater 快速开始](https://leanflutter.dev/documentation/auto_updater/quick-start)、[Sparkle 签名与分发](https://sparkle-project.org/documentation/)、[OSS Python SDK 上传](https://www.alibabacloud.com/help/en/oss/developer-reference/simple-upload-1)、[OSS 禁止覆盖](https://github.com/aliyun/aliyun-oss-python-sdk/blob/master/examples/object_forbid_overwrite.py)。
