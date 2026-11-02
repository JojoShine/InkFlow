import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/editor_session.dart';

void main() {
  test('layout preserves raw text selection and composing range', () {
    final session = EditorSession(text: '第一段\n第二段');
    addTearDown(session.dispose);
    session.controller.value = const TextEditingValue(
      text: '第一段\n第二段',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 4, end: 7),
    );
    final before = session.controller.value;
    session.updateLayout(const EditorLayoutSettings(firstLineIndentEm: 1));
    expect(session.controller.value, before);
    expect(session.controller.text, '第一段\n第二段');
    expect(session.layout.firstLineIndentEm, 1);
  });

  test(
    'native change keeps the input method selection and composing range',
    () {
      final session = EditorSession();
      addTearDown(session.dispose);
      session.applyNativeValue({
        'text': '林晚',
        'selectionBase': 2,
        'selectionExtent': 2,
        'composingStart': 1,
        'composingEnd': 2,
      });
      expect(session.controller.text, '林晚');
      expect(session.controller.selection.extentOffset, 2);
      expect(
        session.controller.value.composing,
        const TextRange(start: 1, end: 2),
      );
    },
  );
}
