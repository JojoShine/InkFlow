import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/ai/ai_context.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';

void main() {
  test(
    'selection snapshot preserves emoji and notices later source edits',
    () async {
      final root = await Directory.systemTemp.createTemp('context-snapshot');
      final work = await WorkRepository.create(
        Directory('${root.path}/work'),
        '书',
      );
      await work.createChapter('甲', text: '甲🪶乙');
      final c = WorkbenchController(Directory('${root.path}/device'));
      await c.initialize();
      await c.openWork(work.root);
      c.session.controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 3,
      );
      final attachment = (await captureAiAttachment(
        controller: c,
        source: AiContextSource.selection,
      ))!;
      expect(attachment.text, '🪶');
      expect(attachment.isStale(c), isFalse);
      c.session.controller.text = '甲🪶丙';
      expect(attachment.text, '🪶');
      expect(attachment.isStale(c), isTrue);
      c.dispose();
      await root.delete(recursive: true);
    },
  );
}
