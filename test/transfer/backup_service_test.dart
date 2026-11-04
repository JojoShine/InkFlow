import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/transfer/backup_service.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/works/work_models.dart';
import 'package:inkflow/features/notes/note_models.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-backup-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'full backup restores independent work with notes links and trash',
    () async {
      final work = await WorkRepository.create(
        Directory('${root.path}/original'),
        '原作品',
      );
      final first = await work.createChapter('第一章', text: '原文甲');
      final second = await work.createChapter('第二章', text: '原文乙');
      await work.trash(first.id);
      final note = NoteRecord(
        id: newId(),
        kind: NoteKind.inspiration,
        title: '灵感',
        body: '钟声',
        chapterId: second.id,
      );
      await work.saveNote(note);
      final backup = File('${root.path}/作品.zip');
      await BackupService.create(work, backup);
      final restored = await BackupService.restore(
        backup,
        Directory('${root.path}/restored'),
      );
      expect(restored.manifest.workId, isNot(work.manifest.workId));
      expect(restored.manifest.title, '原作品');
      expect(restored.manifest.chapterIds, [first.id, second.id]);
      expect(restored.chapters[first.id]!.isDeleted, isTrue);
      expect((await restored.readChapter(first.id)).text, '原文甲');
      expect(restored.notes[note.id]!.chapterId, second.id);
      expect(restored.notes[note.id]!.body, '钟声');
    },
  );
  test(
    'archive traversal is rejected before any content is extracted',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile('../outside.txt', 3, utf8.encode('bad')));
      final source = File('${root.path}/invalid.zip');
      await source.writeAsBytes(ZipEncoder().encode(archive)!);
      await expectLater(
        BackupService.restore(source, Directory('${root.path}/parent')),
        throwsFormatException,
      );
      expect(await File('${root.path}/outside.txt').exists(), isFalse);
      expect(await source.exists(), isTrue);
    },
  );
  test(
    'volume membership and order survive an independent backup restore',
    () async {
      final work = await WorkRepository.create(
        Directory('${root.path}/volume-book'),
        '分卷作品',
      );
      final firstVolume = work.manifest.volumes.single;
      final first = await work.createChapter('第一章', text: '原文甲');
      final secondVolume = await work.createVolume('远行');
      final second = await work.createChapter(
        '第二章',
        text: '原文乙',
        volumeId: secondVolume.id,
      );
      await work.reorderVolumes([secondVolume.id, firstVolume.id]);
      final backup = File('${root.path}/分卷.zip');
      await BackupService.create(work, backup);
      final restored = await BackupService.restore(
        backup,
        Directory('${root.path}/volume-restored'),
      );
      expect(restored.manifest.workId, isNot(work.manifest.workId));
      expect(restored.manifest.volumes.map((v) => v.title), ['远行', '第一卷']);
      expect(restored.manifest.chapterIds, [second.id, first.id]);
      expect(restored.volumeForChapter(first.id), firstVolume.id);
      expect((await restored.readChapter(first.id)).text, '原文甲');
    },
  );
}
