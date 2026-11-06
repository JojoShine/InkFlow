import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/ai/ai_controller.dart';
import 'package:inkflow/features/ai/ai_settings.dart';
import 'package:inkflow/features/ai/ai_settings_dialog.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'ai_controller_test.dart' show MemoryKeys, FakeAiClient;

class DelayedKeys extends MemoryKeys {
  final old = Completer<String?>();
  @override
  Future<bool> contains(String id) => id == oldId
      ? old.future.then((key) => key?.isNotEmpty ?? false)
      : super.contains(id);
  String? oldId;
}

class ReadGuardKeys extends MemoryKeys {
  int reads = 0;
  @override
  Future<String?> read(String id) async {
    reads++;
    throw StateError('Opening settings must not request the secret');
  }
}

void main() {
  Future<void> show(WidgetTester tester, AiController ai) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: inkTheme(const AppearanceSettings()),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAiSettings(context, ai),
              child: const Text('设置'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
  }

  testWidgets('opening connection settings never reads the saved secret', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('ai-status-only'),
    ))!;
    final keys = ReadGuardKeys();
    final ai = AiController(root, credentials: keys, client: FakeAiClient());
    const config = AiSettings(
      provider: AiProvider.deepseek,
      baseUrl: 'https://api.deepseek.com',
      model: 'test',
    );
    ai.activeProvider = config.provider;
    ai.configurations[config.provider] = config;
    keys.keys[config.credentialId] = 'saved-test-key';
    await show(tester, ai);
    expect(keys.reads, 0);
    expect(find.text('已保存到本机'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets(
    'standard connection hides advanced URL and reflects actual saved key',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ai-settings-ui'),
      );
      final keys = MemoryKeys(), client = FakeAiClient();
      final ai = AiController(root!, credentials: keys, client: client);
      const config = AiSettings(
        provider: AiProvider.deepseek,
        baseUrl: 'https://api.deepseek.com',
        model: 'test-model',
      );
      ai.activeProvider = AiProvider.deepseek;
      ai.configurations[AiProvider.deepseek] = config;
      await show(tester, ai);
      expect(find.text('尚未保存密钥'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-base-url')), findsNothing);
      expect(find.text('删除已保存的密钥'), findsNothing);
      expect(client.payloads, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      keys.keys[config.credentialId] = 'never-display-this-secret';
      await show(tester, ai);
      expect(find.text('已保存到本机'), findsOneWidget);
      expect(find.textContaining('never-display-this-secret'), findsNothing);
      await tester.tap(find.text('高级连接设置'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-base-url')),
        'https://different.example/v1',
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未保存密钥'), findsOneWidget);
      expect(client.payloads, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('ai-base-url')),
        config.baseUrl,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ai-model')), '');
      await tester.tap(find.text('删除已保存的密钥'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除密钥'));
      await tester.pumpAndSettle();
      expect(keys.keys, isEmpty);
      expect(find.text('尚未保存密钥'), findsOneWidget);
      expect(client.payloads, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      ai.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );

  testWidgets(
    'required custom address is visible and late key lookup cannot change another provider state',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ai-settings-key-state'),
      );
      final keys = DelayedKeys();
      final ai = AiController(root!, credentials: keys, client: FakeAiClient());
      const config = AiSettings(
        provider: AiProvider.deepseek,
        baseUrl: 'https://api.deepseek.com',
        model: 'test',
      );
      ai.activeProvider = config.provider;
      ai.configurations[config.provider] = config;
      keys.oldId = config.credentialId;
      await show(tester, ai);
      await tester.tap(find.byType(DropdownButtonFormField<AiProvider>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义兼容服务').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-base-url')), findsOneWidget);
      keys.old.complete('old-secret');
      await tester.pumpAndSettle();
      expect(find.text('已保存到本机'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      ai.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}
