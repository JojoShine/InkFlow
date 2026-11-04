import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/works/work_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'editing the current work retains draft, selection and usable manifest versions',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkflow-current-edit-',
      );
      final c = WorkbenchController(Directory('${root.path}/device'));
      try {
        await c.initialize();
        final work = await WorkRepository.create(
          Directory('${root.path}/book'),
          '春',
        );
        await work.createChapter('第一章', text: '原文');
        await c.openWork(work.root);
        c.session.controller.value = const TextEditingValue(
          text: '尚在编辑的正文',
          selection: TextSelection.collapsed(offset: 3),
        );
        final controller = c.session.controller;
        final chapter = c.activeChapter!.id;
        final snapshot = await WorkRepository.open(work.root);
        await c.updateWorkDetails(
          c.preferences.recentWorks.first,
          snapshot,
          title: '春日来信',
          details: const WorkDetails(
            audience: '女频',
            tags: ['悬疑'],
            synopsis: '一封来信',
          ),
        );
        expect(c.session.controller, same(controller));
        expect(controller.text, '尚在编辑的正文');
        expect(controller.selection.extentOffset, 3);
        expect(c.activeChapter!.id, chapter);
        expect(c.work!.manifest.title, '春日来信');
        expect(c.preferences.recentWorks.first.details.synopsis, '一封来信');
        await c.work!.createVolume('第二卷');
        expect(c.work!.manifest.details.synopsis, '一封来信');
        await c.rememberPosition();
        expect(
          (await c.preferencesStore.load()).recentWorks.first.title,
          '春日来信',
        );
        await c.flushAll();
      } finally {
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
