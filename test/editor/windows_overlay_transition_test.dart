import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/editor_session.dart';
import 'package:inkflow/features/editor/novel_editor.dart';

void main() {
  testWidgets(
    'Windows captures viewport before hiding native editor',
    (tester) async {
      final calls = <String>[];
      final session = EditorSession();
      final overlay = ValueNotifier(false);
      const channel = MethodChannel('inkflow/editor/windows');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(
          '${call.method}:${call.arguments is bool ? call.arguments : ''}',
        );
        if (call.method == 'snapshot') {
          return {
            'documentId': 'probe',
            'documentGeneration': session.documentGeneration,
            'width': 2,
            'height': 2,
            'rowBytes': 8,
            'scale': 1.0,
            'pixels': Uint8List.fromList(List.filled(16, 255)),
          };
        }
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: overlay,
            builder: (context, open, _) => NovelEditor(
              session: session,
              layout: session.layout,
              textColor: Colors.black,
              backgroundColor: Colors.white,
              overlayOpen: open,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      calls.clear();
      overlay.value = true;
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(calls, contains('snapshot:'));
      expect(
        calls.indexOf('snapshot:'),
        lessThan(calls.indexOf('visible:false')),
      );
      overlay.value = false;
      await tester.pumpAndSettle();
      expect(calls.lastWhere((c) => c.startsWith('visible:')), 'visible:true');
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      overlay.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );
}
