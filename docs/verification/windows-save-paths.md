# Windows 保存路径回归

旧实现用 dart:io 创建临时文件，再把未经相同处理的路径直接交给 MoveFileExW。Dart 3.11.5 的写文件会将 Windows 路径规范化并转换为扩展长度形式；自定义 FFI 替换没有做这一步。

Windows runner 复现记录：[Actions 41999978042](https://github.com/JojoShine/InkFlow/actions/runs/41999978042)，基线测试提交 `82c04039d423c974cf5126c3c90753822aec51c4`：

- 原文件路径不足 260 字符且可读，附加随机临时文件名后超过 260 字符，RecordStore.write 返回相同的 Windows 错误 3。
- 扩展前缀路径中混合中文和正反斜杠，dart:io 可写可读，但自定义替换返回错误 123。
- 原有短路径与临时占用测试通过，说明旧测试没有覆盖路径处理差异。

修复改为 File.rename，与写文件复用 SDK 的路径规范化。SDK 在 Windows 内部仍使用 MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH，不先删除普通目标文件。保留错误 5/32/33 的有界重试。

历史与恢复记录使用 64 位作品键、32 位章节键；本机数据目录还包含用户目录与应用标识，因此作品放在短路径盘符下也不能保证所有内部临时路径都短。回归覆盖真实长度的键和中文用户目录，而不再只用 work/chapter 短占位符。

验证入口：`flutter test test/storage/windows_file_replace_test.dart test/storage/record_store_test.dart test/storage/history_store_test.dart`，Windows job 使用项目固定的 Flutter 3.41.9。

没有重新解释或强制修改盘符相对路径 D: 的含义，没有要求修改注册表，也没有移动作品目录。
