import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/updates/update_controller.dart';
import 'package:inkflow/features/updates/release_manifest.dart';
import 'package:inkflow/features/updates/update_dialog.dart';
import 'update_controller_test.dart' show FakeUpdater;

void main() {
  testWidgets('about dialog shows installed version, error and working retry', (
    tester,
  ) async {
    final backend = FakeUpdater()..failCheck = true;
    final controller = UpdateController(
      enabled: true,
      backend: backend,
      platform: TargetPlatform.macOS,
      automaticChecks: false,
      loadAppInfo: () async => const AppInfo('InkFlow', '4.5.6', '89'),
      saveBeforeCheck: () async => true,
      prepareForInstall: () async => true,
      quitAfterPrepared: () async {},
      resumeEditing: () async {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppUpdates(context, controller),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('当前版本 4.5.6 (89)'), findsOneWidget);
    expect(backend.checks, 0);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('更新服务暂未就绪，请稍后重试。'), findsOneWidget);
    backend.failCheck = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(backend.checks, 2);
    expect(find.text('正在检查更新…'), findsOneWidget);
    backend.listener!.onUpdaterUpdateNotAvailable(null);
    await tester.pumpAndSettle();
    expect(find.text('当前已是最新版本。'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'download-only dialog offers an actionable check and the correct installation guidance',
    (tester) async {
      final controller = UpdateController(
        enabled: false,
        loadAppInfo: () async => const AppInfo('InkFlow', '0.1.0', '1'),
        checkPublishedRelease: () async => const PublishedRelease('0.1.1', 2),
        openDownloadPage: () async {},
        saveBeforeCheck: () async => true,
        prepareForInstall: () async => true,
        quitAfterPrepared: () async {},
        resumeEditing: () async {},
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppUpdates(context, controller),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '检查更新'))
            .onPressed,
        isNotNull,
      );
      expect(find.textContaining('系统更新窗口'), findsNothing);
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.text('新版本 0.1.1'), findsOneWidget);
      expect(find.text('前往官网下载'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    },
  );
}
