import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  late WorkHandle first, second;
  late String chapter;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-native-busy-');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    first = await WorkRepository.create(Directory('${root.path}/first'), '甲');
    chapter = (await first.createChapter('一', text: '旧稿')).id;
    second = await WorkRepository.create(Directory('${root.path}/second'), '乙');
    await second.createChapter('一', text: '乙稿');
    await c.openWork(first.root);
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });

  testWidgets(
    'busy transition keeps the native editor until delayed composition is saved',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channels = <MethodChannel>[];
      final started = Completer<void>(),
          commit = Completer<Map<String, Object>>();
      var nativeText = '旧稿';
      var blocked = false;
      Map<String, Object> state() => {
        'text': nativeText,
        'selectionBase': nativeText.length,
        'selectionExtent': nativeText.length,
        'isComposing': false,
        'composingStart': -1,
        'composingEnd': -1,
      };
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['id'];
          final channel = MethodChannel('inkflow/editor/$id');
          channels.add(channel);
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'load') {
              nativeText = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'commitComposition' && !blocked) {
              blocked = true;
              started.complete();
              return commit.future;
            }
            if (call.method == 'getState' || call.method == 'commitComposition') {
              return state();
            }
            return null;
          });
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        for (final channel in channels) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });
      await tester.pumpWidget(InkFlowApp(controller: c));
      await tester.pumpAndSettle();
      final editorState = tester.state(find.byType(NovelEditor));
      late Future<void> opening;
      await tester.runAsync(() async {
        opening = c.openWork(second.root);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(started.isCompleted, isTrue);
      final keptMounted =
          find.byType(NovelEditor).evaluate().isNotEmpty &&
          identical(tester.state(find.byType(NovelEditor)), editorState);
      nativeText = '输入法最终提交的中文。';
      commit.complete(state());
      await tester.runAsync(() => opening);
      await tester.pumpAndSettle();
      expect(keptMounted, isTrue);
      expect(
        (await tester.runAsync(() => first.readChapter(chapter)))!.text,
        '输入法最终提交的中文。',
      );
      expect(c.work!.root.path, second.root.path);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
