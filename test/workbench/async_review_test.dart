import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/local_file_store.dart';
import 'package:inkflow/core/storage/record_store.dart';
import 'package:inkflow/core/storage/recovery_store.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

class GateStore extends RecordStore {
  GateStore(super.files);
  String? hold;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<VersionedBytes?> read(String path) async {
    final result = await super.read(path);
    if (path == hold) {
      hold = null;
      started.complete();
      await release.future;
    }
    return result;
  }
}

class GateRecovery extends RecoveryStore {
  GateRecovery(super.root);
  String? hold;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<SessionRecovery?> readSession(String key, String id) async {
    if (id == hold) {
      hold = null;
      started.complete();
      await release.future;
      return SessionRecovery(chapterId: id, text: '甲的恢复稿', baseHash: 'base');
    }
    return super.readSession(key, id);
  }
}

class RecoveryWorkbench extends WorkbenchController {
  RecoveryWorkbench(super.root, this.replacement);
  final RecoveryStore replacement;
  @override
  RecoveryStore get recovery => replacement;
}

void main() {
  test('late external refresh does not reselect an older chapter', () async {
    final root = await Directory.systemTemp.createTemp('refresh-race');
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '书',
    );
    final a = await work.createChapter('甲', text: '甲正文'),
        b = await work.createChapter('乙', text: '乙正文');
    final store = GateStore(LocalFileStore(work.root));
    final c = WorkbenchController(
      Directory('${root.path}/device'),
      openRepository: (dir) =>
          WorkRepository.open(dir, lazy: true, store: store),
    );
    await c.initialize();
    await c.openWork(work.root);
    await File('${work.root.path}/chapters/${a.id}.txt').writeAsString('外部甲');
    store.hold = 'chapters/${a.id}.txt';
    final refreshing = c.checkExternal();
    await store.started.future;
    await c.selectChapter(b.id);
    store.release.complete();
    await refreshing;
    expect(c.activeChapterId, b.id);
    expect(c.session.controller.text, '乙正文');
    c.dispose();
    await root.delete(recursive: true);
  });
  test(
    'late recovery read is never published into a different chapter',
    () async {
      final root = await Directory.systemTemp.createTemp('recovery-race');
      final work = await WorkRepository.create(
        Directory('${root.path}/work'),
        '书',
      );
      final a = await work.createChapter('甲', text: '甲正文'),
          b = await work.createChapter('乙', text: '乙正文');
      final recovery = GateRecovery(Directory('${root.path}/device'));
      final c = RecoveryWorkbench(Directory('${root.path}/device'), recovery);
      await c.initialize();
      await c.openWork(work.root);
      await c.selectChapter(b.id);
      recovery.hold = a.id;
      final selecting = c.selectChapter(a.id);
      await recovery.started.future;
      await c.selectChapter(b.id);
      recovery.release.complete();
      await selecting;
      expect(c.recoveredDraft, isNull);
      expect(c.activeChapterId, b.id);
      c.recoveredDraft = SessionRecovery(
        chapterId: a.id,
        text: '甲恢复',
        baseHash: 'base',
      );
      await expectLater(c.acceptRecoveredDraft(), throwsFormatException);
      expect(c.session.controller.text, '乙正文');
      c.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'a cancelled missing chapter read does not report a stale error',
    () async {
      final root = await Directory.systemTemp.createTemp('cancel-error');
      final work = await WorkRepository.create(
        Directory('${root.path}/work'),
        '书',
      );
      final a = await work.createChapter('甲', text: '保留甲'),
          b = await work.createChapter('乙', text: '暂不可读');
      final store = GateStore(LocalFileStore(work.root));
      final c = WorkbenchController(
        Directory('${root.path}/device'),
        openRepository: (dir) =>
            WorkRepository.open(dir, lazy: true, store: store),
      );
      await c.initialize();
      await c.openWork(work.root);
      await File('${work.root.path}/chapters/${b.id}.txt').delete();
      store.hold = 'chapters/${b.id}.txt';
      final selecting = c.selectChapter(b.id);
      await store.started.future;
      c.cancelLoad();
      store.release.complete();
      await expectLater(selecting, completes);
      expect(c.activeChapterId, a.id);
      expect(c.session.controller.text, '保留甲');
      c.dispose();
      await root.delete(recursive: true);
    },
  );
}
