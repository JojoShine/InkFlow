import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  test(
    'quitting waits for deletion and cannot reinsert the removed work',
    () async {
      final root = await Directory.systemTemp.createTemp('inkflow-trash-quit-');
      final device = Directory('${root.path}/device');
      final c = WorkbenchController(device);
      await c.initialize();
      final work = await WorkRepository.create(
        Directory('${root.path}/book'),
        '甲',
      );
      await work.createChapter('一', text: '已保存');
      await c.openWork(work.root);
      final blocked = Completer<void>(), started = Completer<void>();
      var calls = 0;
      c.session.synchronizeNative = (_) {
        if (++calls == 1) {
          started.complete();
          return blocked.future;
        }
        return Future<void>.value();
      };
      final deleting = c.trashWork(c.preferences.recentWorks.single);
      await started.future;
      final quitting = c.prepareToQuit();
      await Future<void>.delayed(Duration.zero);
      final callsWhileDeleting = calls;
      blocked.complete();
      await deleting;
      expect(await quitting, isTrue);
      expect(callsWhileDeleting, 1);
      final stored = await c.preferencesStore.load();
      expect(stored.recentWorks, isEmpty);
      expect(stored.trashedWorks.single.title, '甲');
      c.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'opening another work waits for an in-flight deletion before attaching its save session',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkflow-trash-switch-',
      );
      final c = WorkbenchController(Directory('${root.path}/device'));
      await c.initialize();
      final first = await WorkRepository.create(
        Directory('${root.path}/first'),
        '甲',
      );
      await first.createChapter('一', text: '甲稿');
      final second = await WorkRepository.create(
        Directory('${root.path}/second'),
        '乙',
      );
      final secondChapter = await second.createChapter('一', text: '乙稿');
      await c.openWork(first.root);
      final blocked = Completer<void>(), started = Completer<void>();
      var calls = 0;
      c.session.synchronizeNative = (_) {
        if (++calls == 1) {
          started.complete();
          return blocked.future;
        }
        return Future<void>.value();
      };
      final deleting = c.trashWork(c.preferences.recentWorks.single);
      await started.future;
      final opening = c.openWork(second.root);
      await Future<void>.delayed(Duration.zero);
      final callsWhileDeleting = calls;
      blocked.complete();
      await Future.wait([deleting, opening]);
      expect(callsWhileDeleting, 1);
      expect(c.work!.root.path, second.root.path);
      c.session.synchronizeNative = null;
      c.session.controller.text = '乙的新稿，必须继续保存。';
      expect(await c.flushAll(), isTrue);
      expect((await second.readChapter(secondChapter.id)).text, '乙的新稿，必须继续保存。');
      expect(c.preferences.trashedWorks.single.title, '甲');
      c.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'failed preference storage does not remove a work from the active library',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkflow-trash-failure-',
      );
      final device = Directory('${root.path}/device');
      final c = WorkbenchController(device);
      await c.initialize();
      final work = await WorkRepository.create(
        Directory('${root.path}/book'),
        '保留这本书',
      );
      await work.createChapter('一', text: '正文');
      await c.openWork(work.root);
      final entry = c.preferences.recentWorks.single;
      await device.rename('${root.path}/device-backup');
      await File(device.path).writeAsString('blocked');
      await expectLater(
        c.trashWork(entry),
        throwsA(isA<FileSystemException>()),
      );
      expect(c.work!.root.path, work.root.path);
      expect(c.preferences.recentWorks.single.path, work.root.path);
      expect(c.preferences.trashedWorks, isEmpty);
      c.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'trashing the current work saves its draft and survives restart with recovery',
    () async {
      final root = await Directory.systemTemp.createTemp('inkflow-work-trash-');
      final device = Directory('${root.path}/device');
      final work = await WorkRepository.create(
        Directory('${root.path}/book'),
        '旧巷',
      );
      final chapter = await work.createChapter('第一章', text: '旧稿');
      final c = WorkbenchController(device);
      await c.initialize();
      await c.openWork(work.root);
      c.session.controller.text = '灯亮了，故事继续。';
      final entry = c.preferences.recentWorks.single;
      await c.trashWork(entry);
      expect(c.work, isNull);
      expect(c.libraryVisible, isTrue);
      expect(c.preferences.recentWorks, isEmpty);
      expect(c.preferences.trashedWorks.single.path, work.root.path);
      expect((await work.readChapter(chapter.id)).text, '灯亮了，故事继续。');
      c.dispose();
      final reopened = WorkbenchController(device);
      await reopened.initialize();
      expect(reopened.work, isNull);
      expect(reopened.preferences.trashedWorks.single.title, '旧巷');
      await reopened.restoreWork(reopened.preferences.trashedWorks.single);
      expect(reopened.preferences.trashedWorks, isEmpty);
      await reopened.openWork(work.root);
      expect(reopened.session.controller.text, '灯亮了，故事继续。');
      reopened.dispose();
      await root.delete(recursive: true);
    },
  );

  test(
    'trashing another work leaves the active manuscript and selection intact',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkflow-other-trash-',
      );
      final c = WorkbenchController(Directory('${root.path}/device'));
      await c.initialize();
      final first = await WorkRepository.create(
        Directory('${root.path}/first'),
        '甲',
      );
      await first.createChapter('一', text: '甲的正文');
      await c.openWork(first.root);
      final firstEntry = c.preferences.recentWorks.single;
      final second = await WorkRepository.create(
        Directory('${root.path}/second'),
        '乙',
      );
      await second.createChapter('一', text: '乙的正文');
      await c.openWork(second.root);
      final before = c.session.controller.value;
      await c.trashWork(firstEntry);
      expect(c.work!.root.path, second.root.path);
      expect(c.session.controller.value, before);
      expect(c.preferences.recentWorks.single.title, '乙');
      await c.openWork(first.root);
      expect(c.preferences.trashedWorks, isEmpty);
      expect(c.preferences.recentWorks.first.title, '甲');
      c.dispose();
      await root.delete(recursive: true);
    },
  );
}
