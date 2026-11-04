import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/record_store.dart';
import 'package:inkflow/features/editor/editor_session.dart';

void main() {
  test('saves after one second idle', () {
    fakeAsync((clock) {
      final written = <String>[];
      final session = EditorSession();
      session.attachDocument('chapter', '', RecordVersion.of([]), (
        text,
        version,
      ) async {
        written.add(text);
        return SaveOutcome(
          SaveState.saved,
          version: RecordVersion.of(utf8.encode(text)),
        );
      });
      session.controller.text = '雨停了';
      clock.elapse(const Duration(milliseconds: 999));
      expect(written, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      clock.flushMicrotasks();
      expect(written, ['雨停了']);
      expect(session.isDirty, isFalse);
      session.dispose();
    });
  });

  test('continuous input saves by ten seconds', () {
    fakeAsync((clock) {
      Duration? firstWrite;
      final session = EditorSession();
      session.attachDocument('chapter', '', RecordVersion.of([]), (
        text,
        version,
      ) async {
        firstWrite ??= clock.elapsed;
        return SaveOutcome(
          SaveState.saved,
          version: RecordVersion.of(utf8.encode(text)),
        );
      });
      for (var i = 0; i < 12; i++) {
        session.controller.text = '文字$i';
        clock.elapse(const Duration(milliseconds: 900));
      }
      clock.flushMicrotasks();
      expect(firstWrite, const Duration(seconds: 10));
      session.dispose();
    });
  });

  test('old completion never marks newer text as saved', () {
    fakeAsync((clock) {
      final first = Completer<SaveOutcome>();
      final second = Completer<SaveOutcome>();
      final written = <String>[];
      final session = EditorSession();
      session.attachDocument('chapter', '', RecordVersion.of([]), (
        text,
        version,
      ) {
        written.add(text);
        return written.length == 1 ? first.future : second.future;
      });
      session.controller.text = '第一版';
      unawaited(session.flush());
      session.controller.text = '第二版';
      first.complete(
        SaveOutcome(
          SaveState.saved,
          version: RecordVersion.of(utf8.encode('第一版')),
        ),
      );
      clock.flushMicrotasks();
      expect(session.isDirty, isTrue);
      expect(session.controller.text, '第二版');
      expect(written, ['第一版', '第二版']);
      second.complete(
        SaveOutcome(
          SaveState.saved,
          version: RecordVersion.of(utf8.encode('第二版')),
        ),
      );
      clock.flushMicrotasks();
      expect(session.isDirty, isFalse);
      session.dispose();
    });
  });

  test('failed close retains the draft for retry or save elsewhere', () async {
    final session = EditorSession();
    session.attachDocument(
      'chapter',
      '',
      RecordVersion.of([]),
      (text, version) async =>
          const SaveOutcome(SaveState.failed, message: '目录失效'),
    );
    session.controller.text = '尚未落盘';
    expect((await session.close()).state, SaveState.failed);
    expect(session.controller.text, '尚未落盘');
    expect(session.isDirty, isTrue);
    session.dispose();
  });
}
