import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/local_file_store.dart';
import 'package:inkflow/core/storage/record_store.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/works/work_models.dart';
import 'package:inkflow/features/transfer/text_transfer.dart';

class CountingStore extends RecordStore {
  CountingStore(super.files);
  final reads = <String>[];
  @override
  Future<VersionedBytes?> read(String path) {
    reads.add(path);
    return super.read(path);
  }
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('demand-test');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('lazy open reads no chapter or note content until requested', () async {
    final original = await WorkRepository.create(root, '大作品');
    final chapter = await original.createChapter('一', text: '第一章正文');
    for (var i = 0; i < 20; i++) {
      await original.saveNote(
        NoteRecord(
          id: newId(),
          kind: NoteKind.inspiration,
          title: '灵感$i',
          body: '不可丢失',
        ),
      );
    }
    final store = CountingStore(LocalFileStore(root));
    final work = await WorkRepository.open(root, lazy: true, store: store);
    expect(
      store.reads.where(
        (p) => p.startsWith('chapters/') || p.startsWith('notes/'),
      ),
      isEmpty,
    );
    expect(work.chapters, isEmpty);
    expect((await work.readChapter(chapter.id)).text, '第一章正文');
    await work.readNextNotes();
    expect(work.notes.length, 16);
    expect(work.notesComplete, isFalse);
    await work.readNextNotes();
    expect(work.notes.length, 20);
    expect(work.notesComplete, isTrue);
  });
  test(
    'export and purge from a partial cache preserve complete content and links',
    () async {
      final original = await WorkRepository.create(root, '全书');
      final chapter = await original.createChapter('未打开', text: '尚未打开的正文');
      final note = NoteRecord(
        id: newId(),
        kind: NoteKind.inspiration,
        title: '关联',
        chapterId: chapter.id,
      );
      await original.saveNote(note);
      final work = await WorkRepository.open(root, lazy: true);
      expect(
        String.fromCharCodes(await TextTransfer.exportWork(work)),
        isNotEmpty,
      );
      await work.trash(chapter.id);
      await work.purge(chapter.id);
      final reopened = await WorkRepository.open(root);
      expect(reopened.notes[note.id]!.chapterId, isNull);
    },
  );
  test('missing lazy chapter never creates an empty replacement', () async {
    final original = await WorkRepository.create(root, '云端');
    final chapter = await original.createChapter('远端', text: '保留');
    await File('${root.path}/chapters/${chapter.id}.txt').delete();
    final work = await WorkRepository.open(root, lazy: true);
    await expectLater(work.readChapter(chapter.id), throwsFormatException);
    expect(
      await File('${root.path}/chapters/${chapter.id}.txt').exists(),
      isFalse,
    );
  });
  test('purging a loaded note keeps lazy pagination complete', () async {
    final original = await WorkRepository.create(root, '资料');
    final note = NoteRecord(
      id: newId(),
      kind: NoteKind.inspiration,
      title: '删除',
    );
    await original.saveNote(note);
    final work = await WorkRepository.open(root, lazy: true);
    await work.readNextNotes();
    await work.trash(note.id);
    await work.purge(note.id);
    expect(work.notesComplete, isTrue);
    expect(await work.readNextNotes(), isEmpty);
  });
}
