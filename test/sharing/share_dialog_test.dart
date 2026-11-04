import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/platform/desktop_services.dart';
import 'package:inkflow/features/sharing/share_dialog.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

class CancelSave extends DesktopServices {
  int saves = 0;
  Uint8List? image;
  @override
  Future<bool> saveShareImage(
    Uint8List bytes,
    String filename, {
    required Directory workRoot,
  }) async {
    saves++;
    image = bytes;
    return false;
  }
}

void main() {
  late Directory root;
  late WorkbenchController c;
  late CancelSave services;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-share-dialog-');
    services = CancelSave();
    c = WorkbenchController(
      Directory('${root.path}/device'),
      services: services,
    );
    await c.initialize();
    final work = await WorkRepository.create(
      Directory('${root.path}/book'),
      '测试作品',
    );
    await work.createChapter('第一章', text: '第一段。\n分享这段。');
    await c.openWork(work.root);
    c.session.controller.selection = const TextSelection(
      baseOffset: 5,
      extentOffset: 10,
    );
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });
  testWidgets(
    'share preview edits and cancelled export leave manuscript and selection intact',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: inkTheme(const AppearanceSettings()),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShareCard(context, c),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final body = find.byKey(const ValueKey('share-body'));
      expect(tester.widget<TextField>(body).controller!.text, '分享这段。');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();
      for (final label in ['花影纸笺', '星夜手记', '像素漫游', '胶片手记']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in ['像素漫游', '胶片手记']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        });
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
              .selected,
          isTrue,
        );
      }
      await tester.enterText(body, '卡片独立编辑。');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存图片'));
      await tester.pumpAndSettle();
      expect(services.saves, 1);
      expect(services.image!.take(4), [137, 80, 78, 71]);
      expect(find.text('图片已保存'), findsNothing);
      expect(c.session.controller.text, '第一段。\n分享这段。');
      expect(
        c.session.controller.selection,
        const TextSelection(baseOffset: 5, extentOffset: 10),
      );
      await tester.enterText(body, List.filled(601, '字').join());
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存图片'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(c.session.controller.text, '第一段。\n分享这段。');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
