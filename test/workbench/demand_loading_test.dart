import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';
import '../works/demand_loading_test.dart' show CountingStore;
import 'package:inkflow/core/storage/local_file_store.dart';

void main() {
  test('opening and focus never index unknown chapter bodies', () async {
    final root = await Directory.systemTemp.createTemp('lazy-controller');
    final original = await WorkRepository.create(
      Directory('${root.path}/work'),
      '大作品',
    );
    final first = await original.createChapter('一', text: '保留正文');
    final unseen = await original.createChapter('二', text: '未打开');
    final store = CountingStore(LocalFileStore(original.root));
    final c = WorkbenchController(
      Directory('${root.path}/device'),
      openRepository: (dir) =>
          WorkRepository.open(dir, lazy: true, store: store),
    );
    await c.initialize();
    await c.openWork(original.root);
    expect(c.activeChapterId, first.id);
    await c.checkExternal();
    expect(store.reads, isNot(contains('chapters/${unseen.id}.txt')));
    expect(c.totalWordsComplete, isFalse);
    c.dispose();
    await root.delete(recursive: true);
  });
  test('cancelled delayed open cannot replace the current work', () async {
    final root = await Directory.systemTemp.createTemp('lazy-cancel');
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '等待',
    );
    final gate = Completer<WorkHandle>();
    final c = WorkbenchController(
      Directory('${root.path}/device'),
      openRepository: (_) => gate.future,
    );
    await c.initialize();
    final opening = c.openWork(work.root);
    await Future<void>.delayed(Duration.zero);
    expect(c.loadProgress, isNotNull);
    c.cancelLoad();
    gate.complete(work);
    await opening;
    expect(c.work, isNull);
    c.dispose();
    await root.delete(recursive: true);
  });
}
