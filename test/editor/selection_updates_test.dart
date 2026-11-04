import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/editor_session.dart';
import 'package:inkflow/core/storage/record_store.dart';

void main() {
  test('unmarking unchanged text commits its statistics once', () {
    final session = EditorSession();
    session.attachDocument(
      'chapter',
      '',
      RecordVersion.of([]),
      (text, version) async => SaveOutcome(SaveState.saved, version: version),
    );
    final value = <Object?, Object?>{
      'text': '你',
      'selectionBase': 1,
      'selectionExtent': 1,
      'composingStart': 1,
      'composingEnd': 1,
      'isComposing': true,
    };
    session.applyNativeValue(value);
    expect(session.statistics.words, 0);
    session.applyNativeValue({...value, 'isComposing': false});
    session.applyNativeValue({...value, 'isComposing': false});
    expect(session.statistics.words, 1);
    session.dispose();
  });
  test(
    'explicit native composition state protects transient collapsed IME ranges',
    () {
      final session = EditorSession();
      session.attachDocument(
        'chapter',
        '',
        RecordVersion.of([]),
        (text, version) async => SaveOutcome(SaveState.saved, version: version),
      );
      session.applyNativeValue({
        'text': 'ni',
        'selectionBase': 2,
        'selectionExtent': 2,
        'composingStart': 2,
        'composingEnd': 2,
        'isComposing': true,
      });
      expect(session.statistics.words, 0);
      session.applyNativeValue({
        'text': '你好',
        'selectionBase': 2,
        'selectionExtent': 2,
        'composingStart': 2,
        'composingEnd': 2,
        'isComposing': false,
      });
      expect(session.statistics.words, 2);
      expect(session.controller.value.composing, TextRange.empty);
      session.dispose();
    },
  );
  test(
    'selection messages cannot prematurely commit or count IME draft text',
    () {
      final session = EditorSession();
      session.attachDocument(
        'chapter',
        '',
        RecordVersion.of([]),
        (text, version) async => SaveOutcome(SaveState.saved, version: version),
      );
      session.applyNativeValue({
        'text': 'ni',
        'selectionBase': 2,
        'selectionExtent': 2,
        'composingStart': 0,
        'composingEnd': 2,
      });
      session.applyNativeSelection({
        'selectionBase': 1,
        'selectionExtent': 1,
        'composingStart': -1,
        'composingEnd': -1,
      });
      expect(session.statistics.words, 0);
      expect(session.controller.value.composing.isValid, isTrue);
      session.applyNativeValue({
        'text': '你好',
        'selectionBase': 2,
        'selectionExtent': 2,
        'composingStart': -1,
        'composingEnd': -1,
      });
      expect(session.statistics.words, 2);
      session.dispose();
    },
  );
  test(
    'selection-only updates keep text and statistics without document rebuilds',
    () {
      final session = EditorSession();
      final text = '旧巷的灯亮了。' * 10000;
      session.attachDocument(
        'chapter',
        text,
        RecordVersion.of([]),
        (text, version) async => SaveOutcome(SaveState.saved, version: version),
      );
      var notifications = 0;
      session.addListener(() => notifications++);
      for (var i = 0; i < 300; i++) {
        session.applyNativeSelection({
          'selectionBase': i,
          'selectionExtent': i + 1,
          'composingStart': -1,
          'composingEnd': -1,
        });
      }
      expect(session.controller.text, same(text));
      expect(session.controller.selection.baseOffset, 299);
      expect(session.statistics.words, 0);
      expect(session.isDirty, isFalse);
      expect(notifications, 0);
      session.applyNativeSelection({
        'selectionBase': text.length + 1,
        'selectionExtent': text.length + 1,
      });
      expect(session.controller.selection.baseOffset, 299);
      session.dispose();
    },
  );

  test('native state synchronizes the final scroll position before saving', () {
    final session = EditorSession();
    session.applyNativeValue({
      'text': '原文',
      'selectionBase': 1,
      'selectionExtent': 1,
      'scrollOffset': 123.5,
    });
    expect(session.scrollOffset, 123.5);
    session.dispose();
  });
}
