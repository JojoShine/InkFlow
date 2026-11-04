import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/startup_transition.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';

void main() {
  testWidgets('startup waits for readiness and never replays over writing', (
    tester,
  ) async {
    var ready = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: inkTheme(const AppearanceSettings()),
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return StartupTransition(ready: ready, child: const Text('稿件'));
          },
        ),
      ),
    );
    expect(find.text('稿件'), findsNothing);
    expect(find.bySemanticsLabel('InkFlow 正在打开书房'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('稿件'), findsNothing);
    update(() => ready = true);
    await tester.pumpAndSettle();
    expect(find.text('稿件'), findsOneWidget);
    update(() => ready = false);
    await tester.pump();
    expect(find.text('稿件'), findsOneWidget);
  });

  testWidgets(
    'reduced motion shows a static mark without delaying ready content',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: inkTheme(const AppearanceSettings()),
          home: const StartupTransition(
            ready: false,
            animationsEnabled: false,
            child: Text('稿件'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('稿件'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          theme: inkTheme(const AppearanceSettings()),
          home: const StartupTransition(
            ready: true,
            animationsEnabled: false,
            child: Text('稿件'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('稿件'), findsOneWidget);
    },
  );
}
