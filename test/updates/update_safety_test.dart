import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';

class FailingSaveController extends WorkbenchController {
  FailingSaveController(super.root);
  @override
  Future<bool> flushAll() async => false;
}

class DelayedSaveController extends WorkbenchController {
  DelayedSaveController(super.root);
  final started = Completer<void>();
  final saved = Completer<bool>();
  @override
  Future<bool> flushAll() {
    started.complete();
    return saved.future;
  }
}

void main() {
  test('preparation locks atomically, shares requests and resumes', () async {
    final root = await Directory.systemTemp.createTemp('inkflow-update-test');
    final c = WorkbenchController(root);
    final locking = Completer<void>();
    final calls = <bool>[];
    c.session.nativeLockForUpdate = (locked) async {
      calls.add(locked);
      if (locked) await locking.future;
    };
    final first = c.prepareForUpdate();
    final second = c.prepareForUpdate();
    expect(c.session.isUpdateLocked, true);
    locking.complete();
    expect(await first, true);
    expect(await second, true);
    expect(await c.prepareForUpdate(), true);
    expect(calls, [true]);
    await c.resumeAfterUpdate();
    expect(c.session.isUpdateLocked, false);
    expect(calls, [true, false]);
    c.dispose();
    await root.delete(recursive: true);
  });

  test('failed native lock restores editing and refuses quit', () async {
    final root = await Directory.systemTemp.createTemp('inkflow-update-test');
    final c = WorkbenchController(root);
    c.session.nativeLockForUpdate = (locked) async {
      if (locked) throw StateError('unavailable');
    };
    expect(await c.prepareToQuit(), false);
    expect(c.session.isUpdateLocked, false);
    c.dispose();
    await root.delete(recursive: true);
  });
  test('cancellation during native lock unlocks its late reply', () async {
    final root = await Directory.systemTemp.createTemp('inkflow-update-test');
    final c = WorkbenchController(root)..busy = false;
    final locking = Completer<void>();
    final calls = <bool>[];
    c.session.nativeLockForUpdate = (locked) async {
      calls.add(locked);
      if (locked) await locking.future;
    };
    final preparation = c.prepareForUpdate();
    final resume = c.resumeAfterUpdate();
    locking.complete();
    expect(await preparation, false);
    await resume;
    expect(calls, [true, false]);
    expect(c.session.isUpdateLocked, false);
    expect(c.busy, false);
    c.dispose();
    await root.delete(recursive: true);
  });
  test('failed save unlocks and refuses installation', () async {
    final root = await Directory.systemTemp.createTemp('inkflow-update-test');
    final c = FailingSaveController(root)..busy = false;
    final calls = <bool>[];
    c.session.nativeLockForUpdate = (locked) async {
      calls.add(locked);
    };
    expect(await c.prepareForUpdate(), false);
    expect(calls, [true, false]);
    expect(c.busy, false);
    expect(c.session.isUpdateLocked, false);
    c.dispose();
    await root.delete(recursive: true);
  });
  test('cancelled slow save cannot later mark installation prepared', () async {
    final root = await Directory.systemTemp.createTemp('inkflow-update-test');
    final c = DelayedSaveController(root)..busy = false;
    final calls = <bool>[];
    c.session.nativeLockForUpdate = (locked) async {
      calls.add(locked);
    };
    final preparation = c.prepareForUpdate();
    await c.started.future;
    await c.resumeAfterUpdate();
    expect(c.session.isUpdateLocked, false);
    expect(c.busy, false);
    c.saved.complete(true);
    expect(await preparation, false);
    expect(calls, [true, false]);
    expect(c.session.isUpdateLocked, false);
    c.dispose();
    await root.delete(recursive: true);
  });
}
