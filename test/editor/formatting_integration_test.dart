import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/editor_session.dart';

void main() {
  test(
    'format replacement is excluded from writing statistics and can be reversed',
    () async {
      final session = EditorSession(text: '　正文  ');
      addTearDown(session.dispose);
      await session.editRange(
        expectedText: '　正文  ',
        range: const TextRange(start: 0, end: 5),
        replacement: '正文',
      );
      expect(session.controller.text, '正文');
      expect(session.statistics.words, 0);
      expect(session.controller.selection.extentOffset, 2);
      await session.editRange(
        expectedText: '正文',
        range: const TextRange(start: 0, end: 2),
        replacement: '　正文  ',
      );
      expect(session.controller.text, '　正文  ');
    },
  );
  test('stale source or composition never changes the document', () async {
    final session = EditorSession(text: '当前正文');
    addTearDown(session.dispose);
    await expectLater(
      session.editRange(
        expectedText: '旧正文',
        range: const TextRange(start: 0, end: 3),
        replacement: '错误',
      ),
      throwsFormatException,
    );
    session.nativeComposing = true;
    await expectLater(
      session.editRange(
        expectedText: '当前正文',
        range: const TextRange(start: 0, end: 4),
        replacement: '错误',
      ),
      throwsFormatException,
    );
    expect(session.controller.text, '当前正文');
  });
  test(
    'native editor owns the single undoable replacement and synchronizes returned state',
    () async {
      final session = EditorSession(text: '　正文  ');
      addTearDown(session.dispose);
      var calls = 0;
      session.applyNativeEdit = (source, range, replacement) async {
        calls++;
        expect(source, '　正文  ');
        expect(range, const TextRange(start: 0, end: 5));
        session.applyNativeValue({
          'text': replacement,
          'selectionBase': 2,
          'selectionExtent': 2,
          'origin': 'format',
          'isComposing': false,
        });
      };
      await session.editRange(
        expectedText: '　正文  ',
        range: const TextRange(start: 0, end: 5),
        replacement: '正文',
      );
      expect(calls, 1);
      expect(session.controller.text, '正文');
    },
  );
}
