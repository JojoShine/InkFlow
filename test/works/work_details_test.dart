import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/works/work_models.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/works/work_codec.dart';
import 'package:inkflow/features/preferences/device_preferences.dart';
import 'package:inkflow/features/transfer/backup_service.dart';
import 'package:inkflow/core/storage/operation_journal.dart';
import '../library/book_cover_test.dart' show tinyPng;

void main() {
  test('stale edit cannot replace newer details or cover metadata', () async {
    final root = await Directory.systemTemp.createTemp('inkflow-edit-stale-');
    addTearDown(() => root.delete(recursive: true));
    final work = await WorkRepository.create(root, '原名');
    final stale = await WorkRepository.open(root);
    await work.updateDetails(
      title: '外部更新',
      details: const WorkDetails(synopsis: '保留这段简介'),
    );
    await expectLater(
      stale.updateDetails(
        title: '旧窗口修改',
        details: const WorkDetails(synopsis: '不应覆盖'),
        cover: tinyPng,
        changeCover: true,
      ),
      throwsA(isA<SaveException>()),
    );
    final latest = await WorkRepository.open(root);
    expect(latest.manifest.title, '外部更新');
    expect(latest.manifest.details.synopsis, '保留这段简介');
    expect(latest.manifest.coverFile, isNull);
  });
  test(
    'work details survive chapters, cover changes, reopening and independent backup restore',
    () async {
      final root = await Directory.systemTemp.createTemp('inkflow-details-');
      addTearDown(() => root.delete(recursive: true));
      const details = WorkDetails(
        audience: '女频',
        tags: ['悬疑', '科幻'],
        synopsis: '雨停之前，她收到了一封来自未来的信。',
      );
      final work = await WorkRepository.create(
        Directory('${root.path}/book'),
        '来信',
        details: details,
      );
      await work.createChapter('第一章', text: '正文');
      await work.updateCover(null);
      final reopened = await WorkRepository.open(work.root);
      expect(reopened.manifest.details.toJson(), details.toJson());
      final backup = File('${root.path}/book.zip');
      await BackupService.create(work, backup);
      final restored = await BackupService.restore(
        backup,
        Directory('${root.path}/restore'),
      );
      expect(restored.manifest.workId, isNot(work.manifest.workId));
      expect(restored.manifest.details.toJson(), details.toJson());
      final entry = RecentWork(
        path: work.root.path,
        workId: work.manifest.workId,
        title: '来信',
        details: details,
      );
      final cached = RecentWork.fromJson(
        entry.position(null, 4, 8).withCover(null).toJson(),
      );
      expect(cached.details.toJson(), details.toJson());
      await work.updateDetails(
        title: '来信续篇',
        details: const WorkDetails(synopsis: '新的故事'),
      );
      expect(
        (await WorkRepository.open(work.root)).manifest.details.synopsis,
        '新的故事',
      );
    },
  );

  test(
    'legacy books default to unrestricted audience; malformed details are rejected',
    () {
      final old = WorkManifest(
        workId: 'a' * 32,
        title: '旧作品',
        chapterIds: [],
      ).toJson()..remove('details');
      expect(
        WorkCodec.decodeManifest(WorkCodec.encode(old)).details.audience,
        '不限',
      );
      expect(
        WorkCodec.decodeManifest(WorkCodec.encode(old)).details.tags,
        isEmpty,
      );
      for (final details in [
        42,
        {
          'tags': [42],
        },
        {'synopsis': false},
        {'audience': []},
      ]) {
        expect(
          () => WorkCodec.decodeManifest(
            WorkCodec.encode({...old, 'details': details}),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
