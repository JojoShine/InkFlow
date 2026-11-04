import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/platform/instance_coordinator.dart';

void main() {
  test(
    'second process activates owner instead of taking editing ownership',
    () async {
      final root = await Directory.systemTemp.createTemp('inkflow-instance-');
      addTearDown(() => root.delete(recursive: true));
      final owner = await Process.start('dart', [
        'run',
        'tool/instance_probe.dart',
        root.path,
      ]);
      addTearDown(() async {
        owner.kill();
        await owner.exitCode;
      });
      final lines = owner.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      expect(
        await lines
            .firstWhere((line) => line.startsWith('INKFLOW:'))
            .timeout(const Duration(seconds: 15)),
        'INKFLOW:primary',
      );
      final activation = lines.firstWhere(
        (line) => line.startsWith('activated:'),
      );
      final lease = await InstanceCoordinator(
        root,
      ).start(requestedPath: '/作品', onActivate: (_) async {});
      addTearDown(lease.close);
      expect(lease.isPrimary, isFalse);
      expect(
        await activation.timeout(const Duration(seconds: 5)),
        'activated:/作品',
      );
    },
  );

  test(
    'an owner killed mid-session does not leave a stale editing lock',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkflow-instance-recover-',
      );
      addTearDown(() => root.delete(recursive: true));
      final owner = await Process.start('dart', [
        'run',
        'tool/instance_probe.dart',
        root.path,
      ]);
      addTearDown(() async {
        owner.kill();
        await owner.exitCode;
      });
      expect(
        await owner.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((line) => line.startsWith('INKFLOW:'))
            .timeout(const Duration(seconds: 15)),
        'INKFLOW:primary',
      );
      owner.kill(ProcessSignal.sigkill);
      await owner.exitCode;
      final lease = await InstanceCoordinator(
        root,
      ).start(onActivate: (_) async {});
      expect(lease.isPrimary, isTrue);
      await lease.close();
    },
  );
}
