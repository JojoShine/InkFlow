import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/ai/ai_controller.dart';
import 'package:inkflow/features/ai/ai_panel.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';

void main() {
  Future<WorkbenchController> showReply(
    WidgetTester tester,
    String answer,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('ai-markdown'),
    ))!;
    final c = WorkbenchController(root);
    c.ai.turns.add(AiTurn(question: '讨论这个片段')..answer = answer);
    await tester.pumpWidget(
      MaterialApp(
        theme: inkTheme(const AppearanceSettings()),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: AiPanel(workbench: c, controller: c.ai, width: 260),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    });
    return c;
  }

  testWidgets('AI renders headings, emphasis and lists instead of raw markup', (
    tester,
  ) async {
    await showReply(tester, '''### 需要补充的信息

请关注**关键选择**。

- 人物目标
- 情节阻碍

1. 选择方向
2. 补足依据''');
    expect(find.text('需要补充的信息', findRichText: true), findsOneWidget);
    expect(find.text('请关注关键选择。', findRichText: true), findsOneWidget);
    expect(find.text('人物目标', findRichText: true), findsOneWidget);
    expect(find.text('补足依据', findRichText: true), findsOneWidget);
    expect(find.textContaining('###'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI renders tables and code in a narrow panel', (tester) async {
    await showReply(tester, '''> 先确认人物动机

| 人物 | 目标 | 阻碍 |
| --- | --- | --- |
| 林晚 | 找到真相 | 缺少线索 |

```text
这是不能因为侧栏宽度而导致溢出的很长一行代码 this_is_a_very_long_unbroken_code_token
```

正文中的 `线索` 和 ~~旧方向~~。''');
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('先确认人物动机', findRichText: true), findsOneWidget);
    expect(find.text('正文中的 线索 和 旧方向。', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a partial streamed reply becomes formatted when completed', (
    tester,
  ) async {
    final c = await showReply(tester, '**思路');
    expect(tester.takeException(), isNull);
    c.ai.turns.single.answer = '**思路整理**\n\n- 下一步';
    c.ai.turns.single.state = 'completed';
    await tester.tap(find.text('总结内容'));
    await tester.pumpAndSettle();
    expect(find.text('思路整理', findRichText: true), findsOneWidget);
    expect(find.text('下一步', findRichText: true), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
