import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/core/storage/operation_journal.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-volumes-');
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'volumes create, rename and reorder while chapters retain their text',
    () async {
      final work = await WorkRepository.create(root, '新作品');
      final firstVolume = work.manifest.volumes.single;
      expect(firstVolume.title, '第一卷');
      final first = await work.createChapter('第一章', text: '原文甲');
      final secondVolume = await work.createVolume('第二卷');
      final second = await work.createChapter(
        '第二章',
        text: '原文乙',
        volumeId: secondVolume.id,
      );
      final third = await work.createChapter(
        '第三章',
        text: '原文丙',
        volumeId: firstVolume.id,
      );
      expect(work.manifest.chapterIds, [first.id, third.id, second.id]);
      await work.renameVolume(secondVolume.id, '远行');
      await work.reorderVolumes([secondVolume.id, firstVolume.id]);
      final reopened = await WorkRepository.open(root);
      expect(reopened.manifest.volumes.map((v) => v.title), ['远行', '第一卷']);
      expect(reopened.manifest.chapterIds, [second.id, first.id, third.id]);
      expect((await reopened.readChapter(first.id)).text, '原文甲');
      expect((await reopened.readChapter(second.id)).text, '原文乙');
      expect(reopened.volumeForChapter(third.id), firstVolume.id);
    },
  );

  test(
    'moving between volumes and ordering within a volume persist without touching manuscript bytes',
    () async {
      final work = await WorkRepository.create(root, '新作品');
      final firstVolume = work.manifest.volumes.single;
      final a = await work.createChapter('甲', text: '保留正文');
      final secondVolume = await work.createVolume('第二卷');
      final b = await work.createChapter('乙', volumeId: secondVolume.id);
      final c = await work.createChapter('丙', volumeId: secondVolume.id);
      final before = await File(
        '${root.path}/chapters/${a.id}.txt',
      ).readAsBytes();
      await work.moveChapter(a.id, secondVolume.id, beforeChapterId: c.id);
      var reopened = await WorkRepository.open(root);
      expect(reopened.manifest.chapterIds, [b.id, a.id, c.id]);
      expect(reopened.volumeForChapter(a.id), secondVolume.id);
      await reopened.moveChapter(c.id, firstVolume.id);
      reopened = await WorkRepository.open(root);
      expect(reopened.manifest.chapterIds, [c.id, b.id, a.id]);
      expect(
        await File('${root.path}/chapters/${a.id}.txt').readAsBytes(),
        before,
      );
      await expectLater(
        reopened.moveChapter(a.id, 'invalid'),
        throwsFormatException,
      );
      expect(reopened.manifest.chapterIds, [c.id, b.id, a.id]);
    },
  );

  test(
    'deleting a volume keeps live and trashed chapters and refuses removing the last volume',
    () async {
      final work = await WorkRepository.create(root, '新作品');
      final firstVolume = work.manifest.volumes.single;
      final other = await work.createVolume('第二卷');
      final a = await work.createChapter('甲', text: '甲正文');
      final b = await work.createChapter('乙', text: '乙正文');
      await work.trash(b.id);
      await work.deleteVolume(firstVolume.id);
      final reopened = await WorkRepository.open(root);
      expect(reopened.manifest.volumes.single.id, other.id);
      expect(reopened.volumeForChapter(a.id), other.id);
      expect(reopened.chapters[b.id]!.isDeleted, isTrue);
      await reopened.restore(b.id);
      expect(reopened.volumeForChapter(b.id), other.id);
      expect((await reopened.readChapter(a.id)).text, '甲正文');
      expect((await reopened.readChapter(b.id)).text, '乙正文');
      await expectLater(reopened.deleteVolume(other.id), throwsFormatException);
    },
  );

  test(
    'legacy books get a first volume and retain membership after reordering and reopening',
    () async {
      final work = await WorkRepository.create(root, '旧作品');
      final chapter = await work.createChapter('旧章节', text: '旧版原文');
      final manifestFile = File('${root.path}/work.json');
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      manifest.remove('volumes');
      manifest.remove('chapterVolumes');
      await manifestFile.writeAsString(jsonEncode(manifest));
      final chapterFile = File('${root.path}/chapters/${chapter.id}.json');
      final metadata =
          jsonDecode(await chapterFile.readAsString()) as Map<String, dynamic>;
      metadata.remove('volumeId');
      await chapterFile.writeAsString(jsonEncode(metadata));
      final legacy = await WorkRepository.open(root);
      final originalVolume = legacy.manifest.volumes.single.id;
      final second = await legacy.createVolume('新卷');
      await legacy.reorderVolumes([second.id, originalVolume]);
      final reopened = await WorkRepository.open(root);
      expect(reopened.volumeForChapter(chapter.id), originalVolume);
      expect((await reopened.readChapter(chapter.id)).text, '旧版原文');
    },
  );

  test(
    'stale deletion cannot remove a volume another handle has moved a chapter into',
    () async {
      final work = await WorkRepository.create(root, '同步作品');
      final second = await work.createVolume('第二卷');
      final chapter = await work.createChapter('章节', text: '保留正文');
      final stale = await WorkRepository.open(root);
      await work.moveChapter(chapter.id, second.id);
      await expectLater(
        stale.deleteVolume(second.id),
        throwsA(isA<SaveException>()),
      );
      final reopened = await WorkRepository.open(root);
      expect(reopened.volumeForChapter(chapter.id), second.id);
      expect((await reopened.readChapter(chapter.id)).text, '保留正文');
    },
  );

  test(
    'volume deletion preserves a concurrent chapter rename without orphaning it',
    () async {
      final work = await WorkRepository.create(root, '同步作品');
      final first = work.manifest.volumes.single;
      final second = await work.createVolume('第二卷');
      final chapter = await work.createChapter('旧标题', text: '保留正文');
      final stale = await WorkRepository.open(root);
      await work.renameChapter(chapter.id, '外部新标题');
      await stale.deleteVolume(first.id);
      final reopened = await WorkRepository.open(root);
      expect(reopened.chapters[chapter.id]!.title, '外部新标题');
      expect(reopened.volumeForChapter(chapter.id), second.id);
      expect((await reopened.readChapter(chapter.id)).text, '保留正文');
    },
  );

  test(
    'simultaneous volume removals always leave chapter membership structurally valid',
    () async {
      final work = await WorkRepository.create(root, '同步作品');
      final first = work.manifest.volumes.single;
      final second = await work.createVolume('第二卷');
      final chapter = await work.createChapter('章节', text: '保留正文');
      final other = await WorkRepository.open(root);
      Future<void> remove(WorkHandle handle, String id) async {
        try {
          await handle.deleteVolume(id);
        } on SaveException {
          /* Another manifest won. */
        }
      }

      await Future.wait([remove(work, first.id), remove(other, second.id)]);
      final reopened = await WorkRepository.open(root);
      expect(reopened.manifest.volumes, hasLength(1));
      expect(
        reopened.volumeForChapter(chapter.id),
        reopened.manifest.volumes.single.id,
      );
      expect((await reopened.readChapter(chapter.id)).text, '保留正文');
    },
  );
}
