import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/scroll_navigation.dart';

void main() {
  test(
    'return action tolerates the last line and small trackpad settling offsets',
    () {
      expect(
        const EditorScrollPosition(
          offset: 3976,
          maxExtent: 4000,
          viewport: 600,
        ).atBottom,
        isTrue,
      );
      expect(
        const EditorScrollPosition(
          offset: 3900,
          maxExtent: 4000,
          viewport: 600,
        ).atBottom,
        isFalse,
      );
      expect(
        const EditorScrollPosition(
          offset: 0,
          maxExtent: 20,
          viewport: 600,
        ).atBottom,
        isFalse,
      );
    },
  );
  testWidgets('drag thumb follows pointer while native metrics are delayed', (
    tester,
  ) async {
    final position = ValueNotifier(
      const EditorScrollPosition(offset: 600, maxExtent: 4000, viewport: 600),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: ScrollNavigation.width,
              height: 500,
              child: ScrollNavigation(
                position: position,
                color: Colors.brown,
                onScrollTo: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final before = tester
        .getTopLeft(find.byKey(const ValueKey('scroll-thumb')))
        .dy;
    await tester.drag(
      find.byKey(const ValueKey('scroll-thumb')),
      const Offset(0, 100),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('scroll-thumb'))).dy,
      greaterThan(before + 60),
    );
    position.value = const EditorScrollPosition(
      offset: 0,
      maxExtent: 4000,
      viewport: 600,
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('scroll-thumb'))).dy,
      lessThan(before),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    position.dispose();
  });
  testWidgets(
    'edge thumb fades, remains draggable, and bottom action returns to zero',
    (tester) async {
      final position = ValueNotifier(
        const EditorScrollPosition(offset: 0, maxExtent: 4000, viewport: 600),
      );
      final requests = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: ScrollNavigation.width,
                height: 500,
                child: ScrollNavigation(
                  position: position,
                  color: Colors.brown,
                  onScrollTo: (offset) {
                    requests.add(offset);
                    position.value = EditorScrollPosition(
                      offset: offset,
                      maxExtent: 4000,
                      viewport: 600,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('scroll-thumb-opacity')),
            )
            .opacity,
        0,
      );
      position.value = const EditorScrollPosition(
        offset: 1200,
        maxExtent: 4000,
        viewport: 600,
      );
      await tester.pump();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('scroll-thumb-opacity')),
            )
            .opacity,
        1,
      );
      await tester.pump(const Duration(milliseconds: 1300));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('scroll-thumb-opacity')),
            )
            .opacity,
        0,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(tester.getCenter(find.byType(ScrollNavigation)));
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('scroll-thumb')),
        const Offset(0, 110),
      );
      await tester.pump();
      expect(requests.last, greaterThan(1200));
      position.value = const EditorScrollPosition(
        offset: 4000,
        maxExtent: 4000,
        viewport: 600,
      );
      await tester.pump();
      expect(find.byTooltip('返回顶部'), findsOneWidget);
      await tester.tap(find.byTooltip('返回顶部'));
      await tester.pump();
      expect(requests.last, 0);
      expect(find.byTooltip('返回顶部'), findsNothing);
      position.value = const EditorScrollPosition(
        offset: 0,
        maxExtent: 0,
        viewport: 600,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('scroll-thumb')), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      position.dispose();
    },
  );
}
