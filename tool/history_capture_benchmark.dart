import 'dart:convert';
import 'dart:io';
import 'package:inkflow/core/storage/history_store.dart';

/// Compares a warm unchanged capture with the same operation forced to scan.
/// This is shared Dart IO work, not a Windows end-to-end exit measurement.
Future<void> main() async {
  final root = await Directory.systemTemp.createTemp(
    'inkflow-history-benchmark-',
  );
  try {
    final history = HistoryStore(root);
    var bytes = <int>[];
    for (var i = 0; i < 100; i++) {
      bytes = utf8.encode('${'正文' * 2000}-$i');
      await history.capture(
        'benchmark',
        'chapter',
        bytes,
        DateTime.utc(2026, 11, 6).add(Duration(seconds: i)),
      );
    }
    final warm = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await history.capture('benchmark', 'chapter', bytes, DateTime.now());
    }
    warm.stop();
    final cold = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      history.invalidate('benchmark', 'chapter');
      await history.capture('benchmark', 'chapter', bytes, DateTime.now());
    }
    cold.stop();
    stdout.writeln(
      jsonEncode({
        'captures': 20,
        'distinct_history_entries': (await history.list(
          'benchmark',
          'chapter',
        )).length,
        'payload_bytes': bytes.length,
        'warm_unchanged_microseconds': warm.elapsedMicroseconds,
        'forced_scan_microseconds': cold.elapsedMicroseconds,
      }),
    );
  } finally {
    await root.delete(recursive: true);
  }
}
