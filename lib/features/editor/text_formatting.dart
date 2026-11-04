import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

class FormattingOptions {
  const FormattingOptions({
    this.trimIndent = true,
    this.trimTrailing = true,
    this.collapseBlankLines = true,
  });
  final bool trimIndent, trimTrailing, collapseBlankLines;
  FormattingOptions copyWith({
    bool? trimIndent,
    bool? trimTrailing,
    bool? collapseBlankLines,
  }) => FormattingOptions(
    trimIndent: trimIndent ?? this.trimIndent,
    trimTrailing: trimTrailing ?? this.trimTrailing,
    collapseBlankLines: collapseBlankLines ?? this.collapseBlankLines,
  );
}

class FormattingPreview {
  const FormattingPreview({
    required this.source,
    required this.range,
    required this.replacement,
    required this.changedLines,
    required this.removedBlankLines,
  });
  final String source, replacement;
  final TextRange range;
  final int changedLines, removedBlankLines;
  String get before => source.substring(range.start, range.end);
  String get formattedText =>
      source.replaceRange(range.start, range.end, replacement);
  bool get hasChanges => before != replacement;
}

abstract final class TextFormatting {
  static FormattingPreview preview(
    String text, {
    TextRange? range,
    FormattingOptions options = const FormattingOptions(),
  }) {
    final scope = range ?? TextRange(start: 0, end: text.length);
    if (!scope.isValid || !scope.isNormalized || scope.end > text.length) {
      throw const FormatException('文字选区已变化，请重新选择');
    }
    var offset = 0;
    final boundaries = <int>{0};
    for (final character in text.characters) {
      offset += character.length;
      boundaries.add(offset);
    }
    if (!boundaries.contains(scope.start) || !boundaries.contains(scope.end)) {
      throw const FormatException('请选择完整字符后再整理');
    }
    final source = text
        .substring(scope.start, scope.end)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final lines = source.split('\n');
    final result = <String>[];
    var changed = 0, removed = 0;
    var previousBlank = false;
    final atStart = scope.start == 0 || '\r\n'.contains(text[scope.start - 1]);
    final atEnd = scope.end == text.length || '\r\n'.contains(text[scope.end]);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (options.trimIndent && (i > 0 || atStart)) {
        line = line.replaceFirst(RegExp(r'^[ \t\u3000]+'), '');
      }
      if (options.trimTrailing && (i < lines.length - 1 || atEnd)) {
        line = line.replaceFirst(RegExp(r'[ \t\u3000]+$'), '');
      }
      final blank = RegExp(r'^[ \t\u3000]*$').hasMatch(line);
      if (options.collapseBlankLines && blank && previousBlank) {
        removed++;
        changed++;
        continue;
      }
      if (line != lines[i]) changed++;
      result.add(line);
      previousBlank = blank;
    }
    if (options.collapseBlankLines &&
        result.length == 1 &&
        RegExp(r'^[ \t\u3000]*$').hasMatch(result.single) &&
        source.contains('\n')) {
      result.add('');
      if (removed > 0) {
        removed--;
        changed--;
      }
    }
    return FormattingPreview(
      source: text,
      range: scope,
      replacement: result.join('\n'),
      changedLines: changed,
      removedBlankLines: removed,
    );
  }
}
