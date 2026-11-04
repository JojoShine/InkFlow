import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/transfer/text_transfer.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  test('strict UTF8 strips BOM and normalizes newlines', () {
    expect(TextTransfer.decode(utf8.encode('\ufeff第一段\r\n第二段')), '第一段\n第二段');
    expect(() => TextTransfer.decode([0xc3]), throwsFormatException);
  });
  test('strict GB18030 supports four-byte supplementary characters', () {
    expect(
      TextTransfer.decode([
        0xd6,
        0xd0,
        0x90,
        0x30,
        0x81,
        0x30,
      ], encoding: 'gb18030'),
      '中\u{10000}',
    );
    expect(
      () => TextTransfer.decode([0x81, 0x30, 0x81], encoding: 'gb18030'),
      throwsFormatException,
    );
  });
  test(
    'whole work export follows live chapter order without layout characters',
    () async {
      final root = await Directory.systemTemp.createTemp('inkflow-export-');
      addTearDown(() => root.delete(recursive: true));
      final work = await WorkRepository.create(root, '书名');
      final first = await work.createChapter('第一章', text: '原文A');
      final second = await work.createChapter('第二章', text: '原文B');
      final third = await work.createChapter('第三章', text: '原文C');
      await work.reorderChapters([third.id, first.id, second.id]);
      await work.trash(first.id);
      expect(
        utf8.decode(await TextTransfer.exportWork(work)),
        '第三章\n\n原文C\n\n第二章\n\n原文B\n',
      );
      expect(
        utf8.decode(await TextTransfer.exportChapter(work, second.id)),
        '原文B',
      );
    },
  );
}
