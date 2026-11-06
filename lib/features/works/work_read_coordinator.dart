import 'dart:async';
import 'dart:collection';

class _MetadataRead {
  _MetadataRead(this.key, this.read);
  final String key;
  final Future<void> Function() read;
  final done = Completer<void>();
}

/// Only metadata uses this queue. An explicit chapter body never waits for it.
class WorkReadCoordinator {
  final _pending = Queue<_MetadataRead>();
  final _requests = <String, Future<void>>{};
  int _active = 0;
  Future<void> run(String key, Future<void> Function() read) {
    if (_requests.containsKey(key)) return _requests[key]!;
    final job = _MetadataRead(key, read);
    _requests[key] = job.done.future;
    _pending.add(job);
    _pump();
    return job.done.future;
  }

  void invalidate() {
    while (_pending.isNotEmpty) {
      _pending.removeFirst().done.complete();
    }
    _requests.clear();
  }

  void _pump() {
    while (_active < 4 && _pending.isNotEmpty) {
      unawaited(_run(_pending.removeFirst()));
    }
  }

  Future<void> _run(_MetadataRead job) async {
    _active++;
    try {
      await job.read();
      job.done.complete();
    } catch (error, stack) {
      job.done.completeError(error, stack);
    } finally {
      _active--;
      if (identical(_requests[job.key], job.done.future)) {
        _requests.remove(job.key);
      }
      _pump();
    }
  }
}
