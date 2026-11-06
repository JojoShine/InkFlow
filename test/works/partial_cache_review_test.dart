import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/works/work_models.dart';
import 'package:inkflow/features/works/work_codec.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/notes/notes_controller.dart';
import 'package:inkflow/core/storage/history_store.dart';

void main() {
  test(
    'restoring a note preserves an unloaded but existing chapter link',
    () async {
      final root = await Directory.systemTemp.createTemp('note-link');
      final original = await WorkRepository.create(root, '书');
      final chapter = await original.createChapter('未加载');
      final note = NoteRecord(
        id: newId(),
        kind: NoteKind.inspiration,
        title: '资料',
        chapterId: chapter.id,
      );
      await original.saveNote(note);
      final work = await WorkRepository.open(root, lazy: true);
      await work.readNextNotes();
      final controller = NotesController(
        work,
        HistoryStore(Directory('${root.path}/device')),
        'work',
      );
      await controller.restoreSnapshot(
        note.id,
        WorkCodec.encode(note.copyWith(body: '恢复').toJson()),
      );
      expect(work.notes[note.id]!.chapterId, chapter.id);
      controller.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'purge refreshes a stale note inventory before removing chapter links',
    () async {
      final root = await Directory.systemTemp.createTemp('note-inventory');
      final original = await WorkRepository.create(root, '书');
      final chapter = await original.createChapter('将删除');
      final work = await WorkRepository.open(root, lazy: true);
      await work.readNextNotes();
      final note = NoteRecord(
        id: newId(),
        kind: NoteKind.inspiration,
        title: '刚同步',
        chapterId: chapter.id,
      );
      await original.saveNote(note);
      await work.trash(chapter.id);
      await work.purge(chapter.id);
      final json =
          jsonDecode(
                await File('${root.path}/notes/${note.id}.json').readAsString(),
              )
              as Map;
      expect(json['chapterId'], isNull);
      await root.delete(recursive: true);
    },
  );
}
