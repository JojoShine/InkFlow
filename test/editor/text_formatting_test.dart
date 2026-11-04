import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/text_formatting.dart';

void main() {
  test(
    'cleans indentation and trailing whitespace, preserving prose and scene markers',
    () {
      final result = TextFormatting.preview(
        '　　第一段  \r\n\r\n\r\n  ——  \r\n\r\n\t👩‍💻 的来信。\t',
      );
      expect(result.formattedText, '第一段\n\n——\n\n👩‍💻 的来信。');
      expect(result.removedBlankLines, 1);
      expect(result.hasChanges, isTrue);
      expect(TextFormatting.preview(result.formattedText).hasChanges, isFalse);
    },
  );
  test(
    'each rule can be disabled without changing punctuation or intentional spacing',
    () {
      const text = '　诗句  \n\n\n  第二句。';
      final result = TextFormatting.preview(
        text,
        options: const FormattingOptions(
          trimIndent: false,
          trimTrailing: false,
          collapseBlankLines: false,
        ),
      );
      expect(result.formattedText, text);
      expect(result.changedLines, 0);
    },
  );
  test(
    'selection leaves outside text and partial-line whitespace untouched',
    () {
      const text = '开头\n  中间段  \n结尾';
      final edit = TextFormatting.preview(
        text,
        range: const TextRange(start: 3, end: 10),
      );
      expect(edit.formattedText, '开头\n中间段\n结尾');
      const partial = '前文  中间  后文';
      expect(
        TextFormatting.preview(
          partial,
          range: const TextRange(start: 3, end: 7),
        ).formattedText,
        partial,
      );
    },
  );
  test('rejects split graphemes and invalid ranges', () {
    expect(
      () => TextFormatting.preview(
        '👩‍💻来了',
        range: const TextRange(start: 2, end: 5),
      ),
      throwsFormatException,
    );
    expect(
      () => TextFormatting.preview(
        '正文',
        range: const TextRange(start: 0, end: 9),
      ),
      throwsFormatException,
    );
    expect(TextFormatting.preview('').hasChanges, isFalse);
    expect(TextFormatting.preview('\n\n\n').formattedText, '\n');
  });
}
