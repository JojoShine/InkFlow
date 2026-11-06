import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';

void main() {
  for (final updating in [false, true]) {
    test(
      '${updating ? "update" : "quit"} hook failure resumes editor and can be retried',
      () async {
        final root = await Directory.systemTemp.createTemp('quit-hook');
        final c = WorkbenchController(root)..busy = false;
        var calls = 0;
        c.beforeQuit = () async {
          calls++;
          return false;
        };
        expect(
          await (updating ? c.prepareForUpdate() : c.prepareToQuit()),
          isFalse,
        );
        expect(c.session.isUpdateLocked, isFalse);
        c.beforeQuit = () async {
          calls++;
          return true;
        };
        expect(
          await (updating ? c.prepareForUpdate() : c.prepareToQuit()),
          isTrue,
        );
        expect(calls, 2);
        c.dispose();
        await root.delete(recursive: true);
      },
    );
  }
}
