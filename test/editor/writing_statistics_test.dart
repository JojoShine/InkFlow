import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/writing_statistics.dart';
import 'package:inkflow/features/editor/editor_session.dart';
import 'package:inkflow/core/storage/record_store.dart';

void main() {
  test(
    'editor session counts committed manual input and excludes native paste and undo',
    () {
      final session = EditorSession();
      session.attachDocument(
        'chapter',
        '原文',
        RecordVersion.of([]),
        (text, version) async => SaveOutcome(SaveState.saved, version: version),
      );
      void native(
        String text, {
        String origin = 'input',
        int composingStart = -1,
        int composingEnd = -1,
      }) {
        session.applyNativeValue({
          'text': text,
          'selectionBase': text.length,
          'selectionExtent': text.length,
          'origin': origin,
          'composingStart': composingStart,
          'composingEnd': composingEnd,
        });
      }

      native('原文ni', composingStart: 2, composingEnd: 4);
      expect(session.statistics.words, 0);
      native('原文你');
      expect(session.statistics.words, 1);
      native('原文你粘贴', origin: 'paste');
      native('原文你', origin: 'undo');
      expect(session.statistics.words, 1);
      native('原文你好');
      expect(session.statistics.words, 2);
      session.replaceText('恢复后的历史文字');
      expect(session.statistics.words, 2);
      session.dispose();
    },
  );
  test(
    'loads, composition, selection and pasted text do not inflate typing rate',
    () {
      var now = Duration.zero;
      final stats = WritingStatistics(now: () => now);
      stats.attach('chapter', '原文');
      stats.observe('原文ni', composing: true);
      expect(stats.words, 0);
      stats.observe('原文你');
      now = const Duration(seconds: 2);
      stats.observe('原文你好');
      now = const Duration(seconds: 4);
      stats.observe('原文你好');
      expect(stats.words, 2);
      expect(stats.wordsPerMinute, 30);
      stats.observe('原文你好粘贴内容', countInput: false);
      expect(stats.words, 2);
      stats.observe('原文你好粘贴内容🙂');
      expect(stats.words, 3);
      stats.dispose();
    },
  );

  test(
    'idle time is capped and writing resumes without counting the idle gap',
    () {
      var now = Duration.zero;
      final stats = WritingStatistics(now: () => now);
      stats.attach('chapter', '');
      stats.observe('春');
      now = const Duration(seconds: 10);
      stats.observe('春天');
      now = const Duration(minutes: 5);
      expect(stats.isPaused, isTrue);
      expect(stats.elapsed, const Duration(seconds: 70));
      stats.observe('春天来了');
      now += const Duration(seconds: 5);
      expect(stats.elapsed, const Duration(seconds: 75));
      expect(stats.words, 4);
      stats.dispose();
    },
  );

  test(
    'chapter switching keeps separate statistics and never counts document loads',
    () {
      var now = Duration.zero;
      final stats = WritingStatistics(now: () => now);
      stats.attach('one', '原文');
      stats.observe('原文甲');
      now = const Duration(seconds: 5);
      stats.attach('two', '另一章');
      expect(stats.words, 0);
      stats.observe('另一章乙');
      now = const Duration(seconds: 8);
      stats.attach('one', '原文甲');
      expect(stats.words, 1);
      expect(stats.elapsed, const Duration(seconds: 5));
      stats.observe('原文甲乙', countInput: false);
      expect(stats.words, 1);
      stats.dispose();
    },
  );
}
