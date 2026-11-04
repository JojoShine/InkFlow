import 'dart:async';
import 'package:flutter/foundation.dart';
import 'word_count.dart';

class WritingStatistics extends ChangeNotifier {
  WritingStatistics({Duration Function()? now}) {
    final clock = Stopwatch()..start();
    _now = now ?? () => clock.elapsed;
  }
  static const idleLimit = Duration(seconds: 60);
  late final Duration Function() _now;
  final _chapters = <String, _WritingTotals>{};
  _WritingTotals? _current;
  String _text = '';
  Duration? _started, _lastInput;
  Timer? _timer;

  int get words => _current?.words ?? 0;
  bool get isPaused => _started == null || _now() - _lastInput! >= idleLimit;
  Duration get elapsed {
    final saved = _current?.elapsed ?? Duration.zero;
    if (_started == null) return saved;
    final current = _now() - _started!;
    final limit = _lastInput! + idleLimit - _started!;
    return saved + (current > limit ? limit : current);
  }

  int get wordsPerMinute => elapsed.inMicroseconds == 0
      ? 0
      : (words * Duration.microsecondsPerMinute / elapsed.inMicroseconds)
            .round();

  void attach(String chapterId, String text) {
    _stop();
    _current = _chapters.putIfAbsent(chapterId, _WritingTotals.new);
    _text = text;
    notifyListeners();
  }

  void observe(String text, {bool composing = false, bool countInput = true}) {
    if (_current == null || text == _text) return;
    if (composing) {
      _activity();
      return;
    }
    if (countInput) {
      var prefix = 0;
      while (prefix < _text.length &&
          prefix < text.length &&
          _text.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
        prefix++;
      }
      var oldEnd = _text.length, newEnd = text.length;
      while (oldEnd > prefix &&
          newEnd > prefix &&
          _text.codeUnitAt(oldEnd - 1) == text.codeUnitAt(newEnd - 1)) {
        oldEnd--;
        newEnd--;
      }
      _current!.words += countWords(text.substring(prefix, newEnd));
      _activity();
    }
    _text = text;
    notifyListeners();
  }

  void _activity() {
    if (isPaused) {
      _stop();
      _started = _now();
    }
    _lastInput = _now();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (isPaused) _stop();
      notifyListeners();
    });
  }

  void _stop() {
    if (_current != null) _current!.elapsed = elapsed;
    _started = _lastInput = null;
    _timer?.cancel();
    _timer = null;
  }

  void pause() {
    _stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _WritingTotals {
  int words = 0;
  Duration elapsed = Duration.zero;
}
