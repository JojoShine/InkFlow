import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/storage/record_store.dart';
import '../../core/storage/operation_journal.dart';
import '../../core/storage/history_store.dart';
import '../works/work_repository.dart';
import '../works/work_codec.dart';
import '../works/work_models.dart';
import 'note_models.dart';

class NotesController extends ChangeNotifier {
  NotesController(this.work, this.history, this.workKey);
  final WorkHandle work;
  final HistoryStore history;
  final String workKey;
  final Map<String, NoteRecord> _drafts = {};
  final Map<String, RecordVersion?> _bases = {};
  final Set<String> _captured = {};
  Timer? _idle, _maximum;
  Future<bool>? _ongoing;
  String? failure;
  bool _disposed = false;
  bool get isDirty => _drafts.isNotEmpty;
  Iterable<NoteRecord> get all => {...work.notes, ..._drafts}.values;
  NoteRecord? find(String id) => _drafts[id] ?? work.notes[id];
  List<NoteRecord> ofKind(NoteKind kind) =>
      all.where((n) => n.kind == kind && !n.isDeleted).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  void update(NoteRecord note) {
    if (!_bases.containsKey(note.id)) {
      _bases[note.id] = work.noteVersion(note.id);
    }
    _drafts[note.id] = note;
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 1), () {
      unawaited(flush());
    });
    _maximum ??= Timer(const Duration(seconds: 10), () {
      unawaited(flush());
    });
    notifyListeners();
  }

  Future<NoteRecord?> create(NoteKind kind, {String? parentId}) async {
    final count = ofKind(kind).length;
    final title = switch (kind) {
      NoteKind.outline => '新大纲',
      NoteKind.character => '新角色',
      NoteKind.inspiration => '新灵感',
    };
    final note = NoteRecord(
      id: newId(),
      kind: kind,
      title: title,
      parentId: parentId,
      order: count,
    );
    try {
      await work.saveNote(note);
      notifyListeners();
      return note;
    } on SaveException catch (error) {
      failure = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> flush() {
    if (_ongoing != null) return _ongoing!;
    _idle?.cancel();
    _maximum?.cancel();
    _idle = _maximum = null;
    late final Future<bool> task;
    task = _saveAll().whenComplete(() {
      if (identical(_ongoing, task)) _ongoing = null;
      if (!_disposed) notifyListeners();
    });
    return _ongoing = task;
  }

  Future<bool> _saveAll() async {
    try {
      while (_drafts.isNotEmpty && !_disposed) {
        final draft = _drafts.values.first;
        final previous = work.notes[draft.id];
        if (previous != null && _captured.add(draft.id)) {
          await history.capture(
            workKey,
            draft.id,
            WorkCodec.encode(previous.toJson()),
            DateTime.now(),
          );
        }
        await work.saveNote(draft, expected: _bases[draft.id]);
        _bases[draft.id] = RecordVersion.of(WorkCodec.encode(draft.toJson()));
        if (identical(_drafts[draft.id], draft)) {
          _drafts.remove(draft.id);
          _bases.remove(draft.id);
        }
      }
      failure = null;
      return true;
    } on SaveException catch (error) {
      failure = error.toString();
    } on FileSystemException catch (error) {
      failure = error.message;
    } on FormatException catch (error) {
      failure = error.message;
    }
    return false;
  }

  Future<void> moveOutline(String id, String? parentId, int index) async {
    final note = find(id)!;
    var parent = parentId;
    final seen = {id};
    while (parent != null) {
      if (!seen.add(parent)) throw const FormatException('不能形成循环大纲');
      parent = find(parent)?.parentId;
    }
    update(note.copyWith(parentId: parentId, order: index));
    await flush();
  }

  void linkInspiration(String id, String? chapterId) =>
      update(find(id)!.copyWith(chapterId: chapterId));

  void discardDraft(String id) {
    _drafts.remove(id);
    _bases.remove(id);
    failure = null;
    notifyListeners();
  }

  Future<void> restoreSnapshot(String id, List<int> bytes) async {
    final previous = find(id);
    if (previous != null) {
      await history.capture(
        workKey,
        id,
        WorkCodec.encode(previous.toJson()),
        DateTime.now(),
      );
    }
    var restored = NoteRecord.decode(bytes);
    if (restored.id != id) throw const FormatException('历史记录不属于此资料');
    if (restored.chapterId != null &&
        !work.chapters.containsKey(restored.chapterId)) {
      restored = restored.copyWith(chapterId: null);
    }
    update(restored);
    await flush();
  }

  @override
  void dispose() {
    _disposed = true;
    _idle?.cancel();
    _maximum?.cancel();
    super.dispose();
  }
}
