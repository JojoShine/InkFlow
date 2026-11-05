import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-native-style-');
    c = WorkbenchController(Directory('${root.path}/device'));
    final work = await WorkRepository.create(Directory('${root.path}/work'), '测试');
    await work.createChapter('第一章', text: '原稿');
    await c.initialize();
    await c.openWork(work.root);
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });
  testWidgets(
    'typing cannot reconfigure the native editor during unchanged theme animations',
    (tester) async {
      const channel = MethodChannel('inkflow/editor/windows');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      var nativeText = '原稿';
      Map<String, Object> state() => {
        'text': nativeText,
        'selectionBase': nativeText.length,
        'selectionExtent': nativeText.length,
        'isComposing': false,
        'composingStart': -1,
        'composingEnd': -1,
      };
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getState' || call.method == 'commitComposition') return state();
        return null;
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(InkFlowApp(controller: c));
      await tester.pumpAndSettle();
      calls.clear();
      nativeText = '原稿继续输入';
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('changed', state())),
        (_) {},
      );
      await tester.pump();
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(
        calls.where((call) => call.method == 'configure'),
        isEmpty,
        reason: 'unchanged native colors must not select and reformat the manuscript',
      );
      expect(calls.where((call) => call.method == 'load'), isEmpty);
      expect(c.session.controller.text, nativeText);
      expect(c.session.controller.selection, TextSelection.collapsed(offset: nativeText.length));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );
}
