import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import '../../core/platform/desktop_services.dart';
import '../../core/storage/history_store.dart';
import '../../core/storage/recovery_store.dart';
import '../../core/storage/record_store.dart';
import '../../core/storage/operation_journal.dart';
import '../appearance/appearance_settings.dart';
import '../editor/editor_session.dart';
import '../updates/update_controller.dart';
import '../editor/text_formatting.dart';
import '../editor/word_count.dart';
import '../library/demo_work.dart';
import '../notes/note_models.dart';
import '../notes/notes_controller.dart';
import '../preferences/device_preferences.dart';
import '../preferences/preferences_store.dart';
import '../works/work_models.dart';
import '../works/work_repository.dart';
import '../works/work_codec.dart';
import '../typing_sound/typing_sound_settings.dart';

class WorkbenchController extends ChangeNotifier {
  WorkbenchController(this.dataRoot, {DesktopServices? services})
    : services = services ?? DesktopServices(),
      preferencesStore = PreferencesStore(dataRoot),
      history = HistoryStore(dataRoot),
      recovery = RecoveryStore(dataRoot) {
    session.addListener(_sessionChanged);
  }

  final Directory dataRoot;
  final DesktopServices services;
  final PreferencesStore preferencesStore;
  final HistoryStore history;
  final RecoveryStore recovery;
  final EditorSession session = EditorSession();
  UpdateController? updates;
  Future<bool>? _updatePreparation;
  bool _updatePrepared = false;
  bool? _beforeUpdateBusy;
  int _updateGeneration = 0;
  DevicePreferences preferences = const DevicePreferences();
  WorkHandle? work;
  NotesController? notes;
  SessionRecovery? recoveredDraft;
  bool busy = true,
      libraryVisible = true,
      leftVisible = true,
      focusMode = false;
  NoteKind? panel = NoteKind.outline;
  bool workMenuOpen = false;
  String? notice;
  int chapterWords = 0;
  final Map<String, int> _counts = {};
  final Map<String, int> _countGenerations = {};
  final Set<String> _changedCounts = {};
  Future<void>? _syncScan;
  bool hasConflicts = false;
  bool _scanCopiesNeeded = false;
  String _observedText = '';
  String? _activeChapterId;
  String? _selectedVolumeId;
  String? get activeVolumeId {
    final target = work;
    if (target == null) return null;
    if (target.manifest.volumes.any((v) => v.id == _selectedVolumeId)) {
      return _selectedVolumeId;
    }
    return _activeChapterId == null
        ? target.manifest.volumes.first.id
        : target.volumeForChapter(_activeChapterId!);
  }

  void selectVolume(String id) {
    _selectedVolumeId = id;
    notifyListeners();
  }

  String get workKey => work == null
      ? ''
      : sha256
            .convert(
              utf8.encode(
                '${p.normalize(work!.root.absolute.path)}|${work!.manifest.workId}',
              ),
            )
            .toString();
  String? get activeChapterId => _activeChapterId;
  ChapterRecord? get activeChapter => work?.chapters[_activeChapterId];
  List<ChapterRecord> get liveChapters => work == null
      ? []
      : work!.manifest.chapterIds
            .map((id) => work!.chapters[id]!)
            .where((chapter) => !chapter.isDeleted)
            .toList();
  int get totalWords => liveChapters.fold(
    0,
    (sum, chapter) =>
        sum +
        (chapter.id == _activeChapterId
            ? chapterWords
            : _counts[chapter.id] ?? 0),
  );
  AppearanceSettings get appearance => preferences.appearance;
  bool _beforeFocusLeft = true;
  NoteKind? _beforeFocusPanel;
  bool _disposed = false;
  String _bookmark = '';
  bool _remember = true;
  Timer? _countTimer, _preferenceTimer, _watchTimer, _historyTimer;
  StreamSubscription<FileSystemEvent>? _watch;
  Future<void> _libraryChanges = Future<void>.value();

  Future<void> _queueLibraryChange(Future<void> Function() action) {
    final task = _libraryChanges.then((_) async {
      final previousBusy = busy;
      busy = true;
      notifyListeners();
      try {
        await action();
      } finally {
        busy = previousBusy;
        if (!_disposed) notifyListeners();
      }
    });
    _libraryChanges = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }

  Future<void> initialize({bool demo = false}) async {
    try {
      preferences = await preferencesStore.load();
      notice = preferencesStore.warning;
      session.updateLayout(preferences.layout);
      if (demo) {
        final directory = Directory(p.join(dataRoot.path, 'demo-work'));
        if (!await File(p.join(directory.path, 'work.json')).exists()) {
          final created = await WorkRepository.create(directory, '槐花落下的时候');
          for (final title in [
            '第一章 旧巷',
            '第二章 来信',
            '第三章 雨停之前',
            '第四章 灯下',
            '第五章 远行',
            '第六章 重逢',
          ]) {
            await created.createChapter(
              title,
              text: title.startsWith('第三章') ? demoText : '在这里继续你的故事。',
            );
          }
          var index = 0;
          for (final title in ['重读来信', '巷口重逢', '未说出口的约定']) {
            await created.saveNote(
              NoteRecord(
                id: newId(),
                kind: NoteKind.outline,
                title: title,
                order: index++,
              ),
            );
          }
        }
        final created = await WorkRepository.open(directory);
        await openWork(
          directory,
          chapterId: created.manifest.chapterIds.length > 2
              ? created.manifest.chapterIds[2]
              : null,
          remember: false,
        );
      } else if (preferences.recentWorks.isNotEmpty) {
        final recent = preferences.recentWorks.first;
        final directory = await services.resolveDirectory(
          recent.path,
          recent.bookmark,
        );
        await openWork(
          directory,
          bookmark: recent.bookmark,
          chapterId: recent.chapterId,
        );
      }
    } on FileSystemException catch (error) {
      notice = error.message;
    } on FormatException catch (error) {
      notice = error.message;
    } on SaveException catch (error) {
      notice = error.toString();
    } on PlatformException catch (error) {
      notice = error.message;
    }
    busy = false;
    notifyListeners();
  }

  Future<void> openWork(
    Directory directory, {
    String bookmark = '',
    String? chapterId,
    bool remember = true,
  }) => _queueLibraryChange(
    () => _openWork(
      directory,
      bookmark: bookmark,
      chapterId: chapterId,
      remember: remember,
    ),
  );

  Future<void> _openWork(
    Directory directory, {
    String bookmark = '',
    String? chapterId,
    bool remember = true,
  }) async {
    if (!await flushAll()) throw const FormatException('请先处理尚未保存的内容');
    final next = await WorkRepository.open(directory);
    await _watch?.cancel();
    notes?.dispose();
    work = next;
    if (next.issues.isNotEmpty) notice = next.issues.join('；');
    _bookmark = bookmark;
    _remember = remember;
    _activeChapterId = null;
    _selectedVolumeId = null;
    _counts.clear();
    _countGenerations.clear();
    _changedCounts.clear();
    notes = NotesController(next, history, workKey)
      ..addListener(notifyListeners);
    libraryVisible = false;
    await scanSyncCopies();
    final live = liveChapters;
    final id = live.any((record) => record.id == chapterId)
        ? chapterId
        : live.firstOrNull?.id;
    if (id != null) await _loadChapter(id);
    _watch = next.watchChanges().listen(
      (event) {
        if (event.path.replaceAll('\\', '/').contains('/.inkflow/')) return;
        final match = RegExp(
          r'^([a-f0-9]{32})\.txt$',
        ).firstMatch(p.basename(event.path));
        if (match != null && match[1] != _activeChapterId) {
          _changedCounts.add(match[1]!);
        }
        final name = p.basename(event.path);
        if (name != 'work.json' &&
            !RegExp(r'^[a-f0-9]{32}\.(txt|json)$').hasMatch(name)) {
          _scanCopiesNeeded = true;
        }
        _watchTimer?.cancel();
        _watchTimer = Timer(const Duration(milliseconds: 300), () {
          unawaited(checkExternal());
        });
      },
      onError: (Object error) {
        notice = '作品目录暂不可访问，当前内容已保留';
        notifyListeners();
      },
    );
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_snapshotAll());
    });
    await rememberPosition();
    unawaited(_indexWords(next));
    notifyListeners();
  }

  Future<void> _indexWords(WorkHandle target) async {
    for (final chapter in target.chapters.values.where(
      (record) => !record.isDeleted,
    )) {
      try {
        final generation = _countGenerations[chapter.id] ?? 0;
        final document = await target.readChapter(chapter.id);
        final count = await compute(countWords, document.text);
        if (_disposed || target != work) return;
        if (generation == (_countGenerations[chapter.id] ?? 0)) {
          _counts[chapter.id] = count;
        }
      } on FileSystemException {
        break;
      } on FormatException {
        break;
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _loadChapter(String id) async {
    final current = work!;
    final document = await current.readChapter(id);
    if (_disposed || current != work) return;
    _activeChapterId = id;
    _selectedVolumeId = work!.volumeForChapter(id);
    final key = workKey;
    session.attachDocument(id, document.text, document.version, (
      text,
      version,
    ) async {
      try {
        await recovery.writeSession(
          key,
          SessionRecovery(
            chapterId: id,
            text: text,
            baseHash: version.hash,
            selectionOffset: session.controller.selection.extentOffset,
            scrollOffset: session.scrollOffset,
          ),
        );
      } on FileSystemException {
        notice = '本机恢复副本暂不可写，正在保存作品正文';
      } on SaveException {
        notice = '本机恢复副本暂不可写，正在保存作品正文';
      }
      final saved = await current.saveChapter(id, text, expected: version);
      if (!saved.isSaved) notice = saved.message;
      return saved;
    }, statisticsKey: '$key/$id');
    chapterWords = await compute(countWords, document.text);
    if (_disposed || current != work) return;
    _counts[id] = chapterWords;
    _observedText = document.text;
    final recent = preferences.recentWorks
        .where((entry) => entry.path == current.root.path)
        .firstOrNull;
    if (recent?.chapterId == id) {
      session.scrollOffset = recent!.scrollOffset;
      session.controller.selection = TextSelection.collapsed(
        offset: recent.selectionOffset.clamp(0, document.text.length),
      );
    }
    recoveredDraft = null;
    try {
      await history.capture(
        key,
        id,
        utf8.encode(document.text),
        DateTime.now(),
      );
      final pending = await recovery.readSession(key, id);
      if (pending != null && pending.text != document.text) {
        recoveredDraft = pending;
      }
    } on FileSystemException {
      notice = '本地历史暂不可访问，原稿未改动';
    } on FormatException catch (error) {
      notice = error.message;
    } on SaveException catch (error) {
      notice = error.toString();
    }
  }

  Future<void> selectChapter(String id) async {
    if (id == _activeChapterId) return;
    if (!await flushAll()) return;
    await _loadChapter(id);
    await rememberPosition();
    notifyListeners();
  }

  void _sessionChanged() {
    final text = session.controller.text;
    if (_observedText != text) {
      _observedText = text;
      final id = _activeChapterId;
      if (id != null) _countGenerations[id] = (_countGenerations[id] ?? 0) + 1;
      _countTimer?.cancel();
      _countTimer = Timer(const Duration(milliseconds: 250), () async {
        final count = await compute(countWords, text);
        if (!_disposed && session.controller.text == text) {
          chapterWords = count;
          if (_activeChapterId != null) _counts[_activeChapterId!] = count;
          notifyListeners();
        }
      });
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> flushAll() async {
    if (work == null) return true;
    final result = await session.close();
    if (!result.isSaved) {
      notice = result.message;
      notifyListeners();
      return false;
    }
    if (notes != null && !await notes!.flush()) {
      notice = notes!.failure;
      notifyListeners();
      return false;
    }
    if (_activeChapterId != null) {
      chapterWords = await compute(countWords, session.controller.text);
      _counts[_activeChapterId!] = chapterWords;
    }
    await _snapshotAll();
    await rememberPosition();
    return true;
  }

  Future<void> applyFormatting(
    FormattingPreview preview, {
    required String expectedWorkKey,
    required String expectedChapterId,
    bool undo = false,
  }) => _queueLibraryChange(() async {
    await session.synchronizeNative?.call(true);
    final expectedText = undo ? preview.formattedText : preview.source;
    void validate() {
      if (workKey != expectedWorkKey ||
          _activeChapterId != expectedChapterId ||
          session.controller.text != expectedText) {
        throw const FormatException('章节或正文已变化，请重新打开排版预览');
      }
    }

    validate();
    await history.capture(
      workKey,
      expectedChapterId,
      utf8.encode(expectedText),
      DateTime.now(),
    );
    validate();
    await session.editRange(
      expectedText: expectedText,
      range: undo
          ? TextRange(
              start: preview.range.start,
              end: preview.range.start + preview.replacement.length,
            )
          : preview.range,
      replacement: undo ? preview.before : preview.replacement,
    );
  });

  Future<bool> prepareToQuit() => prepareForUpdate();

  Future<bool> prepareForUpdate() {
    if (_disposed) return Future.value(false);
    if (_updatePrepared) return Future.value(true);
    return _updatePreparation ??= _prepareForUpdate(
      _updateGeneration,
    ).whenComplete(() => _updatePreparation = null);
  }

  Future<bool> _prepareForUpdate(int generation) async {
    _beforeUpdateBusy ??= busy;
    busy = true;
    notifyListeners();
    try {
      await session.lockForUpdate(true);
      await _libraryChanges;
      if (_disposed || generation != _updateGeneration) return false;
      busy = true;
      notifyListeners();
      final saved = await flushAll();
      if (_disposed || generation != _updateGeneration) return false;
      if (saved) {
        _updatePrepared = true;
        return true;
      }
    } catch (_) {
      if (!_disposed) {
        notice = '未能完成保存，已暂停退出或安装更新。请检查稿件后重试。';
        notifyListeners();
      }
    }
    try {
      await resumeAfterUpdate();
    } catch (_) {
      if (!_disposed) {
        notice = '恢复编辑未完成，请先检查稿件保存状态后重试。';
        notifyListeners();
      }
    }
    return false;
  }

  Future<void> resumeAfterUpdate() async {
    _updateGeneration++;
    _updatePrepared = false;
    // Lock operations are ordered, including replies received after cancellation.
    await session.lockForUpdate(false);
    busy = _beforeUpdateBusy ?? busy;
    _beforeUpdateBusy = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> _snapshotAll() async {
    if (work == null) return;
    try {
      if (_activeChapterId != null && !session.isDirty) {
        await history.capture(
          workKey,
          _activeChapterId!,
          utf8.encode(session.controller.text),
          DateTime.now(),
        );
      }
      for (final note in work!.notes.values.toList()) {
        await history.capture(
          workKey,
          note.id,
          WorkCodec.encode(note.toJson()),
          DateTime.now(),
        );
      }
    } on FileSystemException {
      notice = '稿件已保存，本地历史副本未更新';
    } on SaveException {
      notice = '稿件已保存，本地历史副本未更新';
    }
  }

  Future<void> rememberPosition() async {
    if (work != null && _remember) {
      final entry = RecentWork(
        path: work!.root.path,
        workId: work!.manifest.workId,
        title: work!.manifest.title,
        bookmark: _bookmark,
        coverFile: work!.manifest.coverFile,
        details: work!.manifest.details,
        chapterId: _activeChapterId,
        selectionOffset: session.controller.selection.extentOffset.clamp(
          0,
          session.controller.text.length,
        ),
        scrollOffset: session.scrollOffset,
      );
      preferences = preferences.copyWith(
        trashedWorks: preferences.trashedWorks
            .where((other) => other.path != entry.path)
            .toList(),
        recentWorks: [
          entry,
          ...preferences.recentWorks.where((other) => other.path != entry.path),
        ],
      );
    }
    await persistPreferences();
  }

  Future<void> persistPreferences() async {
    _preferenceTimer?.cancel();
    try {
      await preferencesStore.save(preferences);
    } on FileSystemException {
      notice = '设备设置暂未保存，稿件不受影响';
    } on SaveException {
      notice = '设备设置暂未保存，稿件不受影响';
    }
  }

  Future<bool> chooseLibraryRoot() async {
    final directory = await services.pickWorkDirectory();
    if (directory == null) return false;
    final bookmark = await services.bookmark(directory);
    _preferenceTimer?.cancel();
    final next = preferences.copyWith(
      libraryRootPath: directory.path,
      libraryRootBookmark: bookmark,
    );
    await preferencesStore.save(next);
    preferences = next;
    notifyListeners();
    return true;
  }

  Future<Directory> libraryDirectory() async {
    final path = preferences.libraryRootPath;
    if (path == null) throw const FormatException('请先设置作品书库');
    final directory = await services.resolveDirectory(
      path,
      preferences.libraryRootBookmark,
    );
    if (!await directory.exists()) {
      throw const FileSystemException('书库文件夹暂不可访问，请在书架重新选择位置');
    }
    return directory;
  }

  void updateAppearance(AppearanceSettings appearance) {
    preferences = preferences.copyWith(appearance: appearance);
    _schedulePreferences();
    notifyListeners();
  }

  void updateLayout(EditorLayoutSettings layout) {
    preferences = preferences.copyWith(layout: layout);
    session.updateLayout(layout);
    _schedulePreferences();
    notifyListeners();
  }

  void updateLibraryView(LibraryView view) {
    preferences = preferences.copyWith(libraryView: view);
    _schedulePreferences();
    notifyListeners();
  }

  Future<void> updateWorkDetails(
    RecentWork entry,
    WorkHandle snapshot, {
    required String title,
    required WorkDetails details,
    Uint8List? cover,
    bool changeCover = false,
  }) => _queueLibraryChange(() async {
    if (snapshot.manifest.workId != entry.workId) {
      throw const FormatException('作品身份已变化，请重新打开作品');
    }
    await snapshot.updateDetails(
      title: title,
      details: details,
      cover: cover,
      changeCover: changeCover,
    );
    if (work?.root.path == snapshot.root.path) await work!.reload();
    preferences = preferences.copyWith(
      recentWorks: [
        for (final item in preferences.recentWorks)
          item.path == entry.path ? item.withManifest(snapshot.manifest) : item,
      ],
      trashedWorks: [
        for (final item in preferences.trashedWorks)
          item.path == entry.path ? item.withManifest(snapshot.manifest) : item,
      ],
    );
    await persistPreferences();
  });

  void updateTypingSound(TypingSoundSettings sound) {
    preferences = preferences.copyWith(typingSound: sound);
    _schedulePreferences();
    notifyListeners();
  }

  void _schedulePreferences() {
    _preferenceTimer?.cancel();
    _preferenceTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(persistPreferences());
    });
  }

  void toggleFocus() {
    if (!focusMode) {
      _beforeFocusLeft = leftVisible;
      _beforeFocusPanel = panel;
      leftVisible = false;
      panel = null;
    } else {
      leftVisible = _beforeFocusLeft;
      panel = _beforeFocusPanel;
    }
    focusMode = !focusMode;
    notifyListeners();
  }

  void setPanel(NoteKind? value) {
    panel = value;
    notifyListeners();
  }

  void setWorkMenuOpen(bool value) {
    if (workMenuOpen == value) return;
    workMenuOpen = value;
    notifyListeners();
  }

  void toggleLeft() {
    leftVisible = !leftVisible;
    notifyListeners();
  }

  Future<void> showLibrary() async {
    if (!await flushAll()) return;
    libraryVisible = true;
    session.statistics.pause();
    notifyListeners();
  }

  Future<void> trashWork(RecentWork entry) =>
      _queueLibraryChange(() => _trashWork(entry));

  Future<void> _trashWork(RecentWork entry) async {
    final current = work?.root.path == entry.path;
    if (current && !await flushAll()) {
      throw const FormatException('请先处理未保存的内容，再删除作品');
    }
    final latest =
        preferences.recentWorks
            .where((other) => other.path == entry.path)
            .firstOrNull ??
        entry;
    final next = preferences.copyWith(
      recentWorks: preferences.recentWorks
          .where((other) => other.path != entry.path)
          .toList(),
      trashedWorks: [
        latest,
        ...preferences.trashedWorks.where((other) => other.path != entry.path),
      ],
    );
    _preferenceTimer?.cancel();
    await preferencesStore.save(next);
    preferences = next;
    if (current) {
      await _watch?.cancel();
      _watch = null;
      _watchTimer?.cancel();
      _historyTimer?.cancel();
      _countTimer?.cancel();
      notes?.dispose();
      notes = null;
      work = null;
      _activeChapterId = _selectedVolumeId = null;
      recoveredDraft = null;
      hasConflicts = false;
      focusMode = false;
      libraryVisible = true;
      session.detachDocument();
    }
    notifyListeners();
  }

  Future<void> restoreWork(RecentWork entry) async {
    return _queueLibraryChange(() => _restoreWork(entry));
  }

  Future<void> _restoreWork(RecentWork entry) async {
    final next = preferences.copyWith(
      recentWorks: [
        ...preferences.recentWorks.where((other) => other.path != entry.path),
        entry,
      ],
      trashedWorks: preferences.trashedWorks
          .where((other) => other.path != entry.path)
          .toList(),
    );
    _preferenceTimer?.cancel();
    await preferencesStore.save(next);
    preferences = next;
    notifyListeners();
  }

  void hideLibrary() {
    if (work != null && !busy) {
      libraryVisible = false;
      notifyListeners();
    }
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }

  Future<void> scanSyncCopies() {
    if (_syncScan != null) return _syncScan!;
    late final Future<void> task;
    task = _scanCopies().whenComplete(() {
      if (identical(_syncScan, task)) _syncScan = null;
    });
    return _syncScan = task;
  }

  Future<void> _scanCopies() async {
    final target = work;
    if (target == null) return;
    final candidates = <(File, String)>[];
    await for (final entity in target.root.list()) {
      if (entity is File &&
          p.basename(entity.path) != 'work.json' &&
          p.basename(entity.path).startsWith('work') &&
          entity.path.endsWith('.json')) {
        candidates.add((entity, 'work.json'));
      }
    }
    for (final directoryName in ['chapters', 'notes']) {
      final directory = Directory(p.join(target.root.path, directoryName));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final match = RegExp(
          r'^([a-f0-9]{32}).*\.(txt|json)$',
        ).firstMatch(name);
        if (match == null) continue;
        final id = match[1]!;
        final extension = match[2]!;
        if (name == '$id.$extension') continue;
        if ((directoryName == 'chapters' && target.chapters.containsKey(id)) ||
            (directoryName == 'notes' &&
                target.notes.containsKey(id) &&
                extension == 'json')) {
          candidates.add((entity, '$directoryName/$id.$extension'));
        }
      }
    }
    var found = false;
    for (final (file, canonical) in candidates) {
      final external = await file.readAsBytes();
      final current = await target.store.read(canonical);
      if (RecordVersion.of(external) == current?.version) continue;
      final sourcePath = p
          .relative(file.path, from: target.root.path)
          .replaceAll('\\', '/');
      final id = sha256
          .convert([...utf8.encode(sourcePath), ...external])
          .toString()
          .substring(0, 32);
      final prefix = '.inkflow/conflicts/$id';
      if (await target.store.files.file('$prefix/info.json').exists() ||
          await target.store.files
              .file('.inkflow/resolved-conflicts/$id/info.json')
              .exists()) {
        continue;
      }
      final payloads = <String, List<int>>{
        '$prefix/local.bin': current?.bytes ?? [],
        '$prefix/external.bin': external,
        '$prefix/info.json': utf8.encode(
          jsonEncode({
            'id': id,
            'path': canonical,
            'externalSource': sourcePath,
            'localMissing': current == null,
            'externalMissing': false,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      };
      for (final entry in payloads.entries) {
        final before = await target.store.read(entry.key);
        final saved = await target.store.write(
          entry.key,
          entry.value,
          expected: before?.version,
        );
        if (!saved.isSaved) throw SaveException(saved);
      }
      found = true;
    }
    if (found && !_disposed && work == target) {
      notice = '发现同步副本，原文件均已保留；可从作品菜单比较版本';
      notifyListeners();
    }
    final pending = Directory(
      p.join(target.root.path, '.inkflow', 'conflicts'),
    );
    var unresolved = false;
    if (await pending.exists()) {
      await for (final entry in pending.list()) {
        if (entry is Directory &&
            await File(p.join(entry.path, 'info.json')).exists()) {
          unresolved = true;
          break;
        }
      }
    }
    if (!_disposed && work == target) {
      hasConflicts = unresolved;
      if (unresolved && notice == null) notice = '作品中有未处理的同步冲突，双方副本已保留';
      notifyListeners();
    }
  }

  Future<void> createChapter(
    String title, {
    String text = '',
    String? volumeId,
  }) async {
    if (!await flushAll()) return;
    final chapter = await work!.createChapter(
      title,
      text: text,
      volumeId: volumeId ?? activeVolumeId,
    );
    await _loadChapter(chapter.id);
    notifyListeners();
  }

  Future<void> trashRecord(String id) async {
    if (!await flushAll()) return;
    await work!.trash(id);
    if (id == _activeChapterId) {
      _activeChapterId = null;
      if (liveChapters.isNotEmpty) await _loadChapter(liveChapters.first.id);
    }
    notifyListeners();
  }

  Future<void> restoreRecord(String id) async {
    await work!.restore(id);
    notifyListeners();
  }

  Future<void> purgeRecord(String id) async {
    await work!.purge(id);
    notifyListeners();
  }

  Future<void> restoreHistory(HistoryEntry entry, String recordId) async {
    if (!await flushAll()) return;
    final bytes = await history.read(entry);
    if (work!.chapters.containsKey(recordId)) {
      if (recordId != _activeChapterId) await _loadChapter(recordId);
      await history.capture(
        workKey,
        recordId,
        utf8.encode(session.controller.text),
        DateTime.now(),
      );
      session.replaceText(utf8.decode(bytes));
      await session.flush();
    } else {
      await notes!.restoreSnapshot(recordId, bytes);
    }
    notifyListeners();
  }

  Future<void> acceptRecoveredDraft() async {
    final draft = recoveredDraft;
    if (draft == null) return;
    await history.capture(
      workKey,
      draft.chapterId,
      utf8.encode(session.controller.text),
      DateTime.now(),
    );
    recoveredDraft = null;
    session.replaceText(draft.text, selectionOffset: draft.selectionOffset);
    notifyListeners();
  }

  Future<void> reloadAfterConflict(String path) async {
    final parts = path.split('/');
    if (path.startsWith('notes/') && parts.length == 2) {
      notes?.discardDraft(parts.last.split('.').first);
    }
    await work!.reload();
    if (path == 'chapters/$_activeChapterId.txt' &&
        _activeChapterId != null &&
        work!.chapters.containsKey(_activeChapterId)) {
      final current = await work!.readChapter(_activeChapterId!);
      await recovery.writeSession(
        workKey,
        SessionRecovery(
          chapterId: current.record.id,
          text: current.text,
          baseHash: current.version.hash,
        ),
      );
      await _loadChapter(_activeChapterId!);
    }
    notice = '冲突已处理，双方副本仍保留在作品文件夹中';
    await scanSyncCopies();
    notifyListeners();
  }

  Future<void> checkExternal() async {
    final target = work;
    if (_disposed ||
        target == null ||
        busy ||
        session.isSaving ||
        session.nativeComposing ||
        (!session.controller.value.composing.isCollapsed &&
            session.controller.value.composing.isValid)) {
      return;
    }
    try {
      if (_scanCopiesNeeded) {
        _scanCopiesNeeded = false;
        await scanSyncCopies();
      }
      if (_disposed || target != work) return;
      await target.reload();
      if (_disposed || target != work) return;
      for (final id in {
        ..._changedCounts,
        ...target.manifest.chapterIds.where((id) => !_counts.containsKey(id)),
      }) {
        if (id == _activeChapterId || target.chapters[id]?.isDeleted != false) {
          continue;
        }
        final document = await target.readChapter(id);
        if (_disposed || target != work) return;
        _counts[id] = await compute(countWords, document.text);
        _changedCounts.remove(id);
      }
      if (_disposed || target != work || _activeChapterId == null) return;
      final document = await target.readChapter(_activeChapterId!);
      if (_disposed || target != work) return;
      if (document.version != session.baseVersion) {
        if (session.isDirty) {
          notice = '检测到外部修改，本机草稿已保留；保存时将保留双方版本';
        } else {
          final selection = session.controller.selection.extentOffset;
          await _loadChapter(document.record.id);
          if (_disposed || target != work) return;
          session.controller.selection = TextSelection.collapsed(
            offset: selection.clamp(0, document.text.length),
          );
          notice = '已载入外部更新';
        }
      }
      notifyListeners();
    } on FileSystemException {
      if (_disposed || target != work) return;
      notice = '作品目录暂不可访问，当前内容已保留';
      notifyListeners();
    } on FormatException catch (error) {
      if (_disposed || target != work) return;
      notice = error.message;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _countTimer?.cancel();
    _preferenceTimer?.cancel();
    _watchTimer?.cancel();
    _historyTimer?.cancel();
    unawaited(_watch?.cancel());
    updates?.dispose();
    notes?.dispose();
    session.removeListener(_sessionChanged);
    session.dispose();
    super.dispose();
  }
}
