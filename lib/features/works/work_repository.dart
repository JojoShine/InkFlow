import 'dart:convert';
import 'dart:io';
import '../../core/storage/operation_journal.dart';
import '../../core/storage/local_file_store.dart';
import '../../core/storage/record_store.dart';
import '../notes/note_models.dart';
import 'work_models.dart';
import 'work_codec.dart';

class ChapterDocument {
  const ChapterDocument(this.record, this.text, this.version);
  final ChapterRecord record;
  final String text;
  final RecordVersion version;
}

class WorkRepository {
  static Future<WorkHandle> create(Directory root, String title) async {
    await root.create(recursive: true);
    final store = RecordStore(LocalFileStore(root));
    if (await store.read('work.json') != null) {
      throw const FormatException('这里已有作品，请使用打开作品');
    }
    final manifest = WorkManifest(
      workId: newId(),
      title: title,
      chapterIds: [],
    );
    final result = await store.write(
      'work.json',
      WorkCodec.encodeManifest(manifest),
      expected: null,
    );
    if (!result.isSaved) throw SaveException(result);
    return open(root);
  }

  static Future<WorkHandle> open(Directory root) async {
    final store = RecordStore(LocalFileStore(root));
    final issues = await OperationJournal(store).recover();
    final bytes = await store.read('work.json');
    if (bytes == null) throw const FormatException('找不到作品清单，请选择作品文件夹');
    final work = WorkHandle(root, WorkCodec.decodeManifest(bytes.bytes));
    work.issues.addAll(issues);
    await work.reload();
    return work;
  }
}

const _unspecified = Object();

class WorkHandle {
  WorkHandle(this.root, this.manifest)
    : store = RecordStore(LocalFileStore(root));
  final Directory root;
  final RecordStore store;
  WorkManifest manifest;
  final Map<String, ChapterRecord> chapters = {};
  final Map<String, NoteRecord> notes = {};
  final List<String> issues = [];
  final Map<String, RecordVersion> _versions = {};

  String _chapter(String id) {
    if (!validId(id)) throw const FormatException('章节标识不合法');
    return 'chapters/$id';
  }

  String _note(String id) {
    if (!validId(id)) throw const FormatException('资料标识不合法');
    return 'notes/$id.json';
  }

  RecordVersion? noteVersion(String id) => _versions[_note(id)];

  Future<void> reload() async {
    final raw = await store.read('work.json');
    if (raw == null) throw const FormatException('作品清单暂不可用，原稿未改动');
    final next = WorkCodec.decodeManifest(raw.bytes);
    if (next.workId != manifest.workId) {
      throw const FormatException('作品身份已变化，请重新打开作品');
    }
    final nextChapters = <String, ChapterRecord>{};
    final versions = <String, RecordVersion>{'work.json': raw.version};
    for (final id in next.chapterIds) {
      final path = '${_chapter(id)}.json';
      final record = await store.read(path);
      if (record == null) throw const FormatException('章节信息暂不可用，请等待同步或恢复备份');
      final chapter = WorkCodec.decodeChapter(record.bytes);
      if (chapter.id != id) throw const FormatException('章节记录与文件名不一致');
      nextChapters[id] = chapter;
      versions[path] = record.version;
    }
    final nextNotes = <String, NoteRecord>{};
    final notesDirectory = store.files.file('notes/record.json').parent;
    if (await notesDirectory.exists()) {
      await for (final file in notesDirectory.list()) {
        if (file is! File ||
            !RegExp(r'[/\\][a-f0-9]{32}\.json$').hasMatch(file.path))
          continue;
        final bytes = await file.readAsBytes();
        final note = NoteRecord.decode(bytes);
        if (!file.path.endsWith('${note.id}.json')) {
          throw const FormatException('资料记录与文件名不一致');
        }
        nextNotes[note.id] = note;
        versions[_note(note.id)] = RecordVersion.of(bytes);
      }
    }
    manifest = next;
    chapters
      ..clear()
      ..addAll(nextChapters);
    notes
      ..clear()
      ..addAll(nextNotes);
    _versions.addAll(versions);
  }

  Future<void> _mutate(Map<String, List<int>?> changes) async {
    await OperationJournal(store).apply(
      changes,
      expected: {for (final path in changes.keys) path: _versions[path]},
    );
    for (final entry in changes.entries) {
      if (entry.value == null) {
        _versions.remove(entry.key);
      } else {
        _versions[entry.key] = RecordVersion.of(entry.value!);
      }
    }
  }

  Future<ChapterRecord> createChapter(String title, {String text = ''}) async {
    final chapter = ChapterRecord(id: newId(), title: title);
    final next = manifest.copyWith(
      chapterIds: [...manifest.chapterIds, chapter.id],
    );
    await _mutate({
      '${_chapter(chapter.id)}.txt': utf8.encode(text),
      '${_chapter(chapter.id)}.json': WorkCodec.encode(chapter.toJson()),
      'work.json': WorkCodec.encodeManifest(next),
    });
    manifest = next;
    chapters[chapter.id] = chapter;
    return chapter;
  }

  Future<ChapterDocument> readChapter(String id) async {
    final chapter = chapters[id];
    if (chapter == null) throw const FormatException('章节不存在');
    final raw = await store.read('${_chapter(id)}.txt');
    if (raw == null) throw const FormatException('章节正文暂不可用，请等待同步或恢复备份');
    _versions['${_chapter(id)}.txt'] = raw.version;
    return ChapterDocument(
      chapter,
      utf8.decode(raw.bytes).replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      raw.version,
    );
  }

  Future<SaveOutcome> saveChapter(
    String id,
    String text, {
    required RecordVersion expected,
  }) async {
    if (!chapters.containsKey(id)) throw const FormatException('章节不存在');
    final path = '${_chapter(id)}.txt';
    final result = await store.write(
      path,
      utf8.encode(text),
      expected: expected,
    );
    if (result.isSaved) _versions[path] = result.version!;
    return result;
  }

  Future<void> renameChapter(String id, String title) async {
    final next = chapters[id]!.rename(title);
    await _mutate({'${_chapter(id)}.json': WorkCodec.encode(next.toJson())});
    chapters[id] = next;
  }

  Future<void> reorderChapters(List<String> ids) async {
    if (ids.length != manifest.chapterIds.length ||
        ids.toSet().length != ids.length ||
        !ids.toSet().containsAll(manifest.chapterIds)) {
      throw const FormatException('章节顺序与作品不一致');
    }
    final next = manifest.copyWith(chapterIds: ids);
    await _mutate({'work.json': WorkCodec.encodeManifest(next)});
    manifest = next;
  }

  Future<void> renameWork(String title) async {
    final next = manifest.copyWith(title: title);
    await _mutate({'work.json': WorkCodec.encodeManifest(next)});
    manifest = next;
  }

  Future<void> saveNote(
    NoteRecord note, {
    Object? expected = _unspecified,
  }) async {
    if (!validId(note.id)) throw const FormatException('资料标识不合法');
    if (note.chapterId != null && !chapters.containsKey(note.chapterId)) {
      throw const FormatException('关联章节不存在');
    }
    var parent = note.parentId;
    final visited = {note.id};
    while (parent != null) {
      final record = notes[parent];
      if (!visited.add(parent) ||
          record == null ||
          record.kind != NoteKind.outline) {
        throw const FormatException('大纲层级不合法，不能循环关联');
      }
      parent = record.parentId;
    }
    final path = _note(note.id);
    final result = await store.write(
      path,
      WorkCodec.encode(note.toJson()),
      expected: identical(expected, _unspecified)
          ? _versions[path]
          : expected as RecordVersion?,
    );
    if (!result.isSaved) throw SaveException(result);
    _versions[path] = result.version!;
    notes[note.id] = note;
  }

  Set<String> _subtree(String id) {
    final ids = {id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final note in notes.values) {
        if (note.parentId != null &&
            ids.contains(note.parentId) &&
            ids.add(note.id)) {
          changed = true;
        }
      }
    }
    return ids;
  }

  Future<void> trash(String id) async {
    if (chapters.containsKey(id)) {
      final next = chapters[id]!.trash(DateTime.now());
      await _mutate({'${_chapter(id)}.json': WorkCodec.encode(next.toJson())});
      chapters[id] = next;
    } else {
      final changed = {
        for (final child in _subtree(id))
          child: notes[child]!.copyWith(deletedAt: DateTime.now()),
      };
      await _mutate({
        for (final note in changed.values)
          _note(note.id): WorkCodec.encode(note.toJson()),
      });
      notes.addAll(changed);
    }
  }

  Future<void> restore(String id) async {
    if (chapters.containsKey(id)) {
      final next = chapters[id]!.restore();
      await _mutate({'${_chapter(id)}.json': WorkCodec.encode(next.toJson())});
      chapters[id] = next;
    } else {
      final ids = _subtree(id);
      var parent = notes[id]?.parentId;
      while (parent != null && ids.add(parent)) {
        parent = notes[parent]?.parentId;
      }
      final changed = {
        for (final child in ids) child: notes[child]!.copyWith(deletedAt: null),
      };
      await _mutate({
        for (final note in changed.values)
          _note(note.id): WorkCodec.encode(note.toJson()),
      });
      notes.addAll(changed);
    }
  }

  Future<void> purge(String id) async {
    if (chapters.containsKey(id)) {
      if (!chapters[id]!.isDeleted) throw const FormatException('请先将章节移入回收站');
      final changed = {
        for (final note in notes.values.where((n) => n.chapterId == id))
          note.id: note.copyWith(chapterId: null),
      };
      final next = manifest.copyWith(
        chapterIds: manifest.chapterIds.where((value) => value != id).toList(),
      );
      await store.read('${_chapter(id)}.txt').then((raw) {
        if (raw != null) _versions['${_chapter(id)}.txt'] = raw.version;
      });
      await _mutate({
        for (final note in changed.values)
          _note(note.id): WorkCodec.encode(note.toJson()),
        'work.json': WorkCodec.encodeManifest(next),
        '${_chapter(id)}.txt': null,
        '${_chapter(id)}.json': null,
      });
      notes.addAll(changed);
      manifest = next;
      chapters.remove(id);
    } else {
      if (notes[id]?.isDeleted != true) throw const FormatException('请先移入回收站');
      final ids = _subtree(id);
      await _mutate({for (final child in ids) _note(child): null});
      for (final child in ids) {
        notes.remove(child);
      }
    }
  }

  Stream<FileSystemEvent> watchChanges() => root
      .watch(recursive: true)
      .where(
        (event) => event.path.endsWith('.txt') || event.path.endsWith('.json'),
      );
}
