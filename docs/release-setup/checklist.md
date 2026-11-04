# 正式签名与 OSS 自动更新：一次配置清单

所有值填入 [JojoShine/InkFlow 的 Actions repository secrets](https://github.com/JojoShine/InkFlow/settings/secrets/actions)。不要在聊天、issue 或代码中发送密码、私钥、AccessKey。当前普通 Mac/Windows CI 编译不需要下列签名凭据。

## 需要你准备

| 类别 | Secrets 名称 | 内容 |
| --- | --- | --- |
| Mac 开发者签名 | `MACOS_CERTIFICATE_P12` | Developer ID Application 证书连同私钥导出的 `.p12`，填 base64 内容；仅 `.cer` 不够，不是 Apple Development 或 App Store 证书。需要有效 Apple Developer Program 资格。 |
| 证书解密 | `MACOS_CERTIFICATE_PASSWORD` | 导出上述 p12 时设定的密码。 |
| 签名身份 | `MACOS_SIGN_IDENTITY` | 完整证书名称，如 `Developer ID Application: Your Name (TEAMID)`。 |
| Apple 公证 | `APPLE_ID` | 有权使用该开发团队的 Apple ID 邮箱。 |
| Apple 团队 | `APPLE_TEAM_ID` | 对应证书的 Team ID。 |
| 公证认证 | `APPLE_APP_PASSWORD` | Apple 账号生成的 app-specific password，不是登录密码或验证码。 |
| OSS 上传 | `OSS_ACCESS_KEY_ID` | 专用 RAM 用户 AccessKey ID。 |
| OSS 上传 | `OSS_ACCESS_KEY_SECRET` | 对应 AccessKey Secret；按本目录的 policy 限制在指定前缀。 |

签名身份与 Team ID 都能从正确的证书确定，不需要额外申请另一项服务。Apple 公证也支持 API Key 认证，但当前脚本使用上表的 Apple ID + app-specific password，不要同时准备两套。

## 更新密钥：首次可由我们生成

这些密钥验证更新安装包，和 Apple/Windows 开发者证书不是同一种东西。首次发行可以生成；如以前已经发布过带签名的更新，必须提供并沿用原有更新密钥，不能随意更换。

- `MACOS_ED25519_PRIVATE_KEY`、`MACOS_ED25519_PUBLIC_KEY`：Sparkle 更新密钥。
- `WINDOWS_DSA_PRIVATE_KEY`：当前 WinSparkle 0.8.1 所需的更新密钥。tag 发布会自动从私钥派生公钥。
- `WINDOWS_DSA_PUBLIC_KEY`：可选，用于普通 CI 的公钥注入，不是正式 tag 发布的必填项。

生成后，私钥要加密存入 GitHub Secrets，并另存安全备份，不进入源码。当前密钥尚未生成或配置，不把“可以生成”描述为已配置完成。当前官网的旧预览版未包含更新公钥，首次正式签名版需要手动安装一次，之后才能沿用固定公钥进行应用内自动更新。

## Windows 安装器的开发者签名

当前自动更新必需的是上述 DSA 更新签名。Windows 安装器 Authenticode 签名另行处理：

- 已有可导出的 PFX：配置 `WINDOWS_CERTIFICATE_PFX`（base64）与 `WINDOWS_CERTIFICATE_PASSWORD`。
- 若证书使用云签名或硬件令牌，提供供应商和签名方式的名称即可，流水线需要对应适配，不要导出不可导出的私钥。
- 没有此证书，仍可编译 Windows 并用 DSA 校验更新，但不能宣称安装器有受信任的发布者签名。

## OSS 一次设置

已固定：Bucket `tbtparent-me`，地域杭州，前缀 `Download/inkflow/`，公开 HTTPS 源 `https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/`。

1. 对专用 RAM 上传用户应用 [oss-upload-policy.json](oss-upload-policy.json)：仅此目录的读写、限定前缀列举，以及仅发布锁的删除权限，不使用主账号 AccessKey。
2. 只允许此下载前缀匿名 GetObject，禁止匿名写入；不用公开整个 bucket。
3. 官网跨域读取 OSS 清单时，CORS 允许来源 `https://tbtparent.me`，方法 GET、HEAD；不启用带凭据跨域请求。
4. 当前脚本支持长期 RAM AccessKey。若使用 STS，需要 `OSS_SECURITY_TOKEN` 并保证短期凭据在任务期间有效；过期 STS 不适合作为长期无人值守配置。OIDC 可后续适配，不是当前脚本已支持的认证方式。
5. 密钥可全部先放 repository secrets；若把 OSS 密钥改放 `release` environment，则需要建立该 environment。构建用的签名密钥仍应在 repository secrets 中，因为 build job 不在 release environment。

## 配置后交付

以匹配 pubspec 的版本 tag 发布，构建 → Developer ID 签名/Apple 公证 → 更新签名验证 → OSS 不可变版本包 → feed/history → latest 清单。官网仍保持 `https://tbtparent.me/inkflow/`，不会改动已有站点。第一次正式发布后会替换服务器的临时预览清单，避免遮住 OSS 新版本。

参考：[Apple Developer ID](https://developer.apple.com/developer-id/)、[Apple notarytool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)、[OSS 前缀权限](https://www.alibabacloud.com/help/en/oss/user-guide/access-control-base-on-ram-policy)。
