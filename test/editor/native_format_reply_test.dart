import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/editor_session.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/core/storage/record_store.dart';

void main() {
  testWidgets(
    'late format response cannot enter a newly attached chapter',
    (tester) async {
      final session = EditorSession();
      final reply = Completer<Map<String, Object>>();
      final invoked = Completer<void>();
      void attach(String id, String text) => session.attachDocument(
        id,
        text,
        const RecordVersion('v'),
        (text, base) async => const SaveOutcome(SaveState.saved),
      );
      attach('A', '　原稿');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channels = <MethodChannel>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['id'];
          final channel = MethodChannel('inkflow/editor/$id');
          channels.add(channel);
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'replaceRange') {
              invoked.complete();
              return reply.future;
            }
            return null;
          });
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        for (final c in channels) {
          messenger.setMockMethodCallHandler(c, null);
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NovelEditor(
              session: session,
              layout: session.layout,
              textColor: Colors.black,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final edit = session.editRange(
        expectedText: '　原稿',
        range: const TextRange(start: 0, end: 3),
        replacement: '原稿',
      );
      final rejected = expectLater(edit, throwsFormatException);
      await invoked.future;
      attach('B', 'B 的新稿');
      reply.complete({
        'text': '原稿',
        'selectionBase': 2,
        'selectionExtent': 2,
        'isComposing': false,
        'origin': 'format',
      });
      await rejected;
      expect(session.controller.text, 'B 的新稿');
      expect(session.chapterId, 'B');
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
