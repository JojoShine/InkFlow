import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/local_file_store.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/works/work_models.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'async_review_test.dart' show GateStore;

void main() {
  test(
    'slow note hydration publishes a loading state until the batch completes',
    () async {
      final root = await Directory.systemTemp.createTemp('note-loading');
      final original = await WorkRepository.create(
        Directory('${root.path}/work'),
        '书',
      );
      await original.createChapter('甲');
      final note = NoteRecord(
        id: newId(),
        kind: NoteKind.inspiration,
        title: '远端资料',
      );
      await original.saveNote(note);
      final store = GateStore(LocalFileStore(original.root))
        ..hold = 'notes/${note.id}.json';
      final c = WorkbenchController(
        Directory('${root.path}/device'),
        openRepository: (dir) =>
            WorkRepository.open(dir, lazy: true, store: store),
      );
      await c.initialize();
      await c.openWork(original.root);
      await store.started.future;
      expect(c.notesLoading, isTrue);
      store.release.complete();
      await c.work!.readNextNotes();
      await Future<void>.delayed(Duration.zero);
      expect(c.notesLoading, isFalse);
      c.dispose();
      await root.delete(recursive: true);
    },
  );
}
