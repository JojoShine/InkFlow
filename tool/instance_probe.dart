import 'dart:io';
import 'package:inkflow/core/platform/instance_coordinator.dart';

Future<void> main(List<String> arguments) async {
  final lease = await InstanceCoordinator(Directory(arguments.single)).start(
    onActivate: (path) async {
      stdout.writeln('activated:$path');
    },
  );
  stdout.writeln(lease.isPrimary ? '\nINKFLOW:primary' : '\nINKFLOW:secondary');
  if (lease.isPrimary) await stdin.first;
  await lease.close();
}
