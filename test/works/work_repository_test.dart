import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/works/work_models.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('inkflow-work-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'chapter rename and reorder survive opening without changing text files',
    () async {
      final work = await WorkRepository.create(dir, '新作品');
      final first = await work.createChapter('第一章', text: '雨停了。');
      final second = await work.createChapter('第二章', text: '有人敲门。');
      await work.renameChapter(first.id, '旧巷');
      await work.reorderChapters([second.id, first.id]);
      final reopened = await WorkRepository.open(dir);
      expect(reopened.manifest.chapterIds, [second.id, first.id]);
      expect((await reopened.readChapter(first.id)).text, '雨停了。');
      expect(reopened.chapters[first.id]!.title, '旧巷');
      expect(
        await File('${dir.path}/chapters/${first.id}.txt').exists(),
        isTrue,
      );
    },
  );
  test('trash keeps inspiration and permanent removal unlinks it', () async {
    final work = await WorkRepository.create(dir, '新作品');
    final chapter = await work.createChapter('第一章');
    final note = NoteRecord(
      id: newId(),
      kind: NoteKind.inspiration,
      title: '雨后',
      body: '先写声音',
      chapterId: chapter.id,
    );
    await work.saveNote(note);
    await work.trash(chapter.id);
    expect(work.notes[note.id]!.chapterId, chapter.id);
    expect(work.notes[note.id]!.body, '先写声音');
    await work.purge(chapter.id);
    final reopened = await WorkRepository.open(dir);
    expect(reopened.notes[note.id]!.chapterId, isNull);
    expect(reopened.notes[note.id]!.body, '先写声音');
    expect(
      await File('${dir.path}/chapters/${chapter.id}.txt').exists(),
      isFalse,
    );
  });
  test(
    'outline parent cycles are refused and last valid records stay intact',
    () async {
      final work = await WorkRepository.create(dir, '新作品');
      final parent = NoteRecord(
        id: newId(),
        kind: NoteKind.outline,
        title: '第一卷',
      );
      final child = NoteRecord(
        id: newId(),
        kind: NoteKind.outline,
        title: '起点',
        parentId: parent.id,
      );
      await work.saveNote(parent);
      await work.saveNote(child);
      await expectLater(
        work.saveNote(parent.copyWith(parentId: child.id)),
        throwsFormatException,
      );
      expect(
        (await WorkRepository.open(dir)).notes[parent.id]!.parentId,
        isNull,
      );
    },
  );
  test(
    'a missing chapter metadata file never becomes an empty replacement',
    () async {
      final work = await WorkRepository.create(dir, '新作品');
      final chapter = await work.createChapter('第一章', text: '留下原文');
      await File('${dir.path}/chapters/${chapter.id}.json').delete();
      await expectLater(WorkRepository.open(dir), throwsFormatException);
      expect(
        await File('${dir.path}/chapters/${chapter.id}.txt').readAsString(),
        '留下原文',
      );
      expect(
        await File('${dir.path}/chapters/${chapter.id}.json').exists(),
        isFalse,
      );
    },
  );
}
