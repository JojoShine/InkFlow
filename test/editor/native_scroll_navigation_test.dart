import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/editor_session.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/core/storage/record_store.dart';

void main() {
  testWidgets(
    'native scroll metrics drive edge controls without changing text or selection',
    (tester) async {
      final session = EditorSession();
      session.attachDocument(
        'A',
        '保留正文',
        const RecordVersion('v'),
        (text, version) async => const SaveOutcome(SaveState.saved),
      );
      session.controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      late MethodChannel channel;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          channel = MethodChannel(
            'inkflow/editor/${(call.arguments as Map)['id']}',
          );
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        messenger.setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NovelEditor(
              session: session,
              layout: session.layout,
              textColor: Colors.brown,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> metrics(String id) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('scrolled', {
              'documentId': id,
              'documentGeneration': session.documentGeneration,
              'offset': 4000.0,
              'maxExtent': 4000.0,
              'viewport': 500.0,
            }),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await metrics('wrong');
      expect(find.byTooltip('返回顶部'), findsNothing);
      await metrics('A');
      expect(find.byTooltip('返回顶部'), findsOneWidget);
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('selection', {
            'selectionBase': 2,
            'selectionExtent': 3,
            'composingStart': -1,
            'composingEnd': -1,
          }),
        ),
        (_) {},
      );
      await tester.pump();
      expect(
        find.byTooltip('返回顶部'),
        findsOneWidget,
        reason: 'selection messages must keep the known scroll range',
      );
      await tester.tap(find.byTooltip('返回顶部'));
      await tester.pump();
      final request =
          calls.lastWhere((c) => c.method == 'scrollTo').arguments as Map;
      expect(request['offset'], 0);
      expect(request['documentId'], 'A');
      expect(session.controller.text, '保留正文');
      expect(
        session.controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 3),
      );
      expect(session.statistics.words, 0);
      expect(session.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
