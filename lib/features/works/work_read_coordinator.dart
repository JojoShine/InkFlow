import 'dart:async';
import 'dart:collection';

/// Only metadata uses this queue. An explicit chapter body never waits for it.
class WorkReadCoordinator {
  final _pending = Queue<void Function()>();
  final _requests = <String, Future<void>>{};
  int _active = 0;

  Future<void> run(String key, Future<void> Function() read) {
    if (_requests.containsKey(key)) return _requests[key]!;
    final done = Completer<void>();
    _requests[key] = done.future;
    _pending.add(() async {
      _active++;
      try {
        await read();
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _active--;
        _requests.remove(key);
        _pump();
      }
    });
    _pump();
    return done.future;
  }

  void _pump() {
    while (_active < 4 && _pending.isNotEmpty) {
      _pending.removeFirst()();
    }
  }
}
