import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/works/work_read_coordinator.dart';

void main() {
  test(
    'invalidate drops queued cloud reads while active reads finish',
    () async {
      final queue = WorkReadCoordinator(), gate = Completer<void>();
      var started = 0;
      final pending = List.generate(
        12,
        (i) => queue.run('$i', () async {
          started++;
          await gate.future;
        }),
      );
      expect(started, 4);
      queue.invalidate();
      gate.complete();
      await Future.wait(pending);
      expect(started, 4);
    },
  );
}
