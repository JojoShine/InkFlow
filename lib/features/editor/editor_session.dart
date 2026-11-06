import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import '../../core/storage/record_store.dart';
import '../../core/typography.dart';
import 'writing_statistics.dart';

class EditorLayoutSettings {
  const EditorLayoutSettings({
    this.fontFamily = inkFontFamily,
    this.fontSize = 16,
    this.lineHeight = 1.5,
    this.paragraphGap = 8,
    this.firstLineIndentEm = 2,
    this.maxWidth = 760,
  });

  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final double paragraphGap;
  final double firstLineIndentEm;
  final double maxWidth;

  EditorLayoutSettings copyWith({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? paragraphGap,
    double? firstLineIndentEm,
    double? maxWidth,
  }) => EditorLayoutSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphGap: paragraphGap ?? this.paragraphGap,
    firstLineIndentEm: firstLineIndentEm ?? this.firstLineIndentEm,
    maxWidth: maxWidth ?? this.maxWidth,
  );

  Map<String, Object> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'paragraphGap': paragraphGap,
    'firstLineIndentEm': firstLineIndentEm,
    'maxWidth': maxWidth,
  };
}

class EditorSession extends ChangeNotifier {
  EditorSession({String text = ''})
    : controller = TextEditingController(text: text),
      _savedText = text,
      _observedText = text {
    controller.addListener(_changed);
  }

  final TextEditingController controller;
  final statistics = WritingStatistics();
  Future<void> Function()? previewTypingSound;
  String _inputOrigin = 'input';
  EditorLayoutSettings layout = const EditorLayoutSettings();

  String _savedText;
  String _observedText;
  String? chapterId;
  double scrollOffset = 0;
  bool nativeComposing = false;
  bool isUpdateLocked = false;
  Future<void> Function(bool locked)? nativeLockForUpdate;
  Future<void> _nativeLockOperation = Future<void>.value();

  Future<void> lockForUpdate(bool locked) {
    if (locked) {
      isUpdateLocked = true;
      if (!_disposed) notifyListeners();
    }
    final operation = _nativeLockOperation.then((_) async {
      await nativeLockForUpdate?.call(locked);
      isUpdateLocked = locked;
      if (!_disposed) notifyListeners();
    });
    _nativeLockOperation = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> Function(bool commitComposition)? synchronizeNative;
  Future<void> Function(
    String expectedText,
    TextRange range,
    String replacement,
  )?
  applyNativeEdit;
  RecordVersion? baseVersion;
  SaveOutcome lastOutcome = const SaveOutcome(SaveState.saved);
  Future<SaveOutcome> Function(String, RecordVersion)? _save;
  Future<SaveOutcome>? _ongoing;
  Timer? _idle;
  Timer? _maximum;
  bool _loading = false;
  bool _disposed = false;
  int _generation = 0;

  int get documentGeneration => _generation;

  bool get isDirty => controller.text != _savedText;
  bool get isSaving => _ongoing != null;

  void attachDocument(
    String id,
    String text,
    RecordVersion version,
    Future<SaveOutcome> Function(String, RecordVersion) save, {
    String? statisticsKey,
  }) {
    _generation++;
    _cancelTimers();
    _save = save;
    chapterId = id;
    scrollOffset = 0;
    baseVersion = version;
    _savedText = _observedText = text;
    lastOutcome = SaveOutcome(SaveState.saved, version: version);
    _loading = true;
    statistics.attach(statisticsKey ?? id, text);
    controller.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _loading = false;
    notifyListeners();
  }

  void _cancelTimers() {
    _idle?.cancel();
    _maximum?.cancel();
    _idle = _maximum = null;
  }

  void detachDocument() {
    _generation++;
    _cancelTimers();
    _save = null;
    chapterId = null;
    baseVersion = null;
    nativeComposing = false;
    _savedText = _observedText = controller.text;
    statistics.pause();
  }

  void _changed() {
    final textChanged = controller.text != _observedText;
    if (!_loading) {
      statistics.observe(
        controller.text,
        composing:
            nativeComposing ||
            (controller.value.composing.isValid &&
                !controller.value.composing.isCollapsed),
        countInput: _inputOrigin == 'input',
      );
    }
    if (!_loading && textChanged) {
      _observedText = controller.text;
      if (isDirty && _save != null && lastOutcome.state != SaveState.conflict) {
        _idle?.cancel();
        _idle = Timer(const Duration(seconds: 1), () {
          unawaited(flush());
        });
        _maximum ??= Timer(const Duration(seconds: 10), () {
          unawaited(flush());
        });
      } else if (!isDirty) {
        _cancelTimers();
      }
    }
    if (!_loading && textChanged) notifyListeners();
  }

  Future<SaveOutcome> flush() {
    if (_ongoing != null) return _ongoing!;
    late final Future<SaveOutcome> task;
    task = _drain().whenComplete(() {
      if (identical(_ongoing, task)) _ongoing = null;
      if (!_disposed) notifyListeners();
    });
    _ongoing = task;
    if (!_disposed) notifyListeners();
    return task;
  }

  Future<SaveOutcome> _drain() async {
    _cancelTimers();
    final synchronize = synchronizeNative;
    if (synchronize != null) await synchronize(false);
    final generation = _generation;
    while (!_disposed && isDirty) {
      final text = controller.text;
      final save = _save;
      final version = baseVersion;
      if (save == null || version == null) {
        return const SaveOutcome(SaveState.failed, message: '请先打开作品');
      }
      SaveOutcome result;
      try {
        result = await save(text, version);
      } on FileSystemException catch (error) {
        result = SaveOutcome(SaveState.failed, message: error.message);
      } on FormatException catch (error) {
        result = SaveOutcome(SaveState.failed, message: error.message);
      }
      if (_disposed || generation != _generation) return result;
      lastOutcome = result;
      if (!result.isSaved) {
        _cancelTimers();
        return result;
      }
      baseVersion = result.version!;
      _savedText = text;
      notifyListeners();
    }
    _cancelTimers();
    lastOutcome = SaveOutcome(SaveState.saved, version: baseVersion);
    return lastOutcome;
  }

  Future<SaveOutcome> close() async {
    await synchronizeNative?.call(true);
    return flush();
  }

  void updateLayout(EditorLayoutSettings next) {
    layout = next;
    notifyListeners();
  }

  void applyNativeValue(Map<Object?, Object?> value) {
    if (value['scrollOffset'] case final num offset) {
      scrollOffset = offset.toDouble();
    }
    final text = value['text'] as String;
    final base = (value['selectionBase'] as int).clamp(0, text.length);
    final extent = (value['selectionExtent'] as int).clamp(0, text.length);
    final start = value['composingStart'] as int? ?? -1;
    final end = value['composingEnd'] as int? ?? -1;
    final previousOrigin = _inputOrigin;
    final previousComposing = nativeComposing;
    nativeComposing = value['isComposing'] as bool? ?? false;
    _inputOrigin = value['origin'] as String? ?? 'input';
    try {
      final next = TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: base, extentOffset: extent),
        composing:
            value['isComposing'] != false &&
                start >= 0 &&
                end >= start &&
                end <= text.length
            ? TextRange(start: start, end: end)
            : TextRange.empty,
      );
      final unchanged = controller.value == next;
      controller.value = next;
      if (unchanged && previousComposing != nativeComposing) _changed();
    } finally {
      _inputOrigin = previousOrigin;
    }
  }

  void applyNativeSelection(Map<Object?, Object?> selection) {
    final length = controller.text.length;
    if ((selection['selectionBase'] as int) > length ||
        (selection['selectionExtent'] as int) > length) {
      return;
    }
    controller.value = controller.value.copyWith(
      selection: TextSelection(
        baseOffset: selection['selectionBase'] as int,
        extentOffset: selection['selectionExtent'] as int,
      ),
    );
  }

  Future<void> editRange({
    required String expectedText,
    required TextRange range,
    required String replacement,
  }) async {
    if (isUpdateLocked ||
        controller.text != expectedText ||
        nativeComposing ||
        (controller.value.composing.isValid &&
            !controller.value.composing.isCollapsed) ||
        !range.isValid ||
        !range.isNormalized ||
        range.end > expectedText.length) {
      throw const FormatException('正文或输入状态已变化，请重新打开排版预览');
    }
    if (applyNativeEdit case final edit?) {
      await edit(expectedText, range, replacement);
    } else {
      final offset = range.start + replacement.length;
      applyNativeValue({
        'text': expectedText.replaceRange(range.start, range.end, replacement),
        'selectionBase': offset,
        'selectionExtent': offset,
        'origin': 'format',
        'isComposing': false,
      });
    }
  }

  void replaceText(String text, {int selectionOffset = 0}) {
    final offset = selectionOffset.clamp(0, text.length);
    applyNativeValue({
      'text': text,
      'selectionBase': offset,
      'selectionExtent': offset,
      'origin': 'restore',
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    controller.removeListener(_changed);
    statistics.dispose();
    controller.dispose();
    super.dispose();
  }
}
