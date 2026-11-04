import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/editor_session.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/features/typing_sound/typing_sound_settings.dart';
import 'package:inkflow/features/typing_sound/typing_sound_assets.dart';

void main() {
  testWidgets(
    'macOS manuscript passes outside taps through while a menu is open',
    (tester) async {
      final session = EditorSession();
      session.controller.value = const TextEditingValue(
        text: '保留正文',
        selection: TextSelection.collapsed(offset: 2),
      );
      final anchorOpen = ValueNotifier(false);
      final sound = ValueNotifier(const TypingSoundSettings());
      final soundCalls = <Map<Object?, Object?>>[];
      await tester.runAsync(
        () => typingSoundBytes(
          const TypingSoundSettings(preset: TypingSoundPreset.soft),
        ),
      );
      final interactive = <bool>[];
      final channels = <MethodChannel>[];
      var created = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          created++;
          final id = (call.arguments as Map)['id'];
          final channel = MethodChannel('inkflow/editor/$id');
          channels.add(channel);
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'interactive') {
              interactive.add(call.arguments as bool);
            }
            if (call.method == 'sound') {
              soundCalls.add(call.arguments as Map<Object?, Object?>);
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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showMenu<String>(
                      context: context,
                      position: const RelativeRect.fromLTRB(0, 50, 500, 0),
                      items: const [
                        PopupMenuItem(value: 'new', child: Text('新建卷')),
                      ],
                    ),
                    child: const Text('新建'),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([anchorOpen, sound]),
                      builder: (context, _) => NovelEditor(
                        session: session,
                        layout: session.layout,
                        textColor: Colors.black,
                        backgroundColor: Colors.transparent,
                        overlayOpen: anchorOpen.value,
                        typingSound: sound.value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(interactive, [true]);
      anchorOpen.value = true;
      await tester.pumpAndSettle();
      expect(interactive.last, isFalse);
      anchorOpen.value = false;
      await tester.pumpAndSettle();
      expect(interactive.last, isTrue);
      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();
      expect(interactive.last, isFalse);
      await tester.tapAt(const Offset(500, 400));
      await tester.pumpAndSettle();
      expect(find.text('新建卷'), findsNothing);
      expect(interactive.last, isTrue);
      expect(created, 1);
      expect(session.controller.text, '保留正文');
      expect(session.controller.selection.baseOffset, 2);
      expect(soundCalls.first['bytes'], isNull);
      sound.value = const TypingSoundSettings(preset: TypingSoundPreset.soft);
      await tester.pumpAndSettle();
      await tester.runAsync(session.previewTypingSound!);
      await tester.pumpAndSettle();
      expect(soundCalls.last['preview'], isTrue);
      expect((soundCalls.last['bytes'] as List<int>).length, greaterThan(44));
      expect(created, 1);
      expect(session.controller.text, '保留正文');
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      anchorOpen.dispose();
      sound.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
