import 'dart:async';
import 'package:flutter/material.dart';
import 'update_controller.dart';

Future<void> showAppUpdates(
  BuildContext context,
  UpdateController controller,
) async {
  unawaited(controller.initialize());
  await showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(controller: controller),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.controller});
  final UpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final info = controller.appInfo;
      return AlertDialog(
        title: const Text('关于与更新'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info?.name ?? 'InkFlow', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(info == null ? '正在读取版本信息…' : '当前版本 ${info.versionLabel}'),
              if (controller.availableVersion case final version?) ...[
                const SizedBox(height: 8),
                Text('新版本 $version'),
              ],
              const SizedBox(height: 24),
              Semantics(liveRegion: true, child: Text(controller.message)),
              const SizedBox(height: 12),
              Text(
                '下载和安装进度将在系统更新窗口中显示。安装前会保存稿件，完成后重新启动应用。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: controller.canCheck ? controller.checkForUpdates : null,
            child: Text(
              controller.status == UpdateStatus.error ? '重试' : '检查更新',
            ),
          ),
        ],
      );
    },
  );
}
