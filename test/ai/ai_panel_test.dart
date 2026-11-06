import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/ai/ai_panel.dart';
import 'package:inkflow/features/ai/ai_context.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  testWidgets('AI modes preserve the draft and show the selected context', (
    tester,
  ) async {
    if (Platform.environment['INKFLOW_UI_CAPTURE'] != null) {
      await tester.runAsync(() async {
        final textFont = FontLoader('Songti SC')
          ..addFont(
            File(
              '/System/Library/Fonts/Supplemental/Songti.ttc',
            ).readAsBytes().then((b) => ByteData.sublistView(b)),
          );
        await textFont.load();
        final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
          ..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          );
        await icons.load();
      });
    }
    final fixture = await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('ai-panel');
      final work = await WorkRepository.create(
        Directory('${root.path}/work'),
        '小说',
      );
      await work.createChapter('一', text: '原稿');
      final c = WorkbenchController(Directory('${root.path}/device'));
      await c.initialize();
      await c.openWork(work.root);
      return (root, c);
    });
    final (root, c) = fixture!;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: InkFlowApp(controller: c),
      ),
    );
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.byType(AiPanel), findsOneWidget);
    expect(find.text('配置 AI'), findsOneWidget);
    c.updatePanelWidths(notes: 260);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '发送（Enter）',
            ),
          )
          .onPressed,
      isNull,
    );
    final output = Platform.environment['INKFLOW_UI_CAPTURE'];
    if (output != null) {
      await tester.runAsync(() async {
        final image =
            await (captureKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '我已经写好的讨论问题');
    await tester.tap(find.text('评价内容'));
    await tester.pump();
    expect(c.ai.draft, '我已经写好的讨论问题');
    expect(c.ai.purpose, AiPurpose.evaluate);
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('ai-purpose-evaluate')))
          .properties
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('ai-context-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-source-chapter')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('当前章节'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-context-menu')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckedPopupMenuItem<AiContextSource>>(
            find.byKey(const ValueKey('ai-source-chapter')),
          )
          .checked,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除附加内容'));
    await tester.pump();
    expect(c.ai.attachment, isNull);
    expect(c.ai.turns, isEmpty);
    expect(c.session.controller.text, '原稿');
    await tester.tap(composer);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      c.ai.failure,
      isNotNull,
      reason: 'Enter must invoke send, not insert a newline',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
