import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/ai/ai_credentials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('inkflow/ai-credentials');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'saved keys are reused and cache changes only after successful writes',
    () async {
      final stored = <String, String>{'connection': 'saved-test-key'};
      var reads = 0, rejectWrite = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map;
        final id = args['id'] as String;
        switch (call.method) {
          case 'contains':
            return stored.containsKey(id);
          case 'read':
            reads++;
            return stored[id];
          case 'write':
            if (rejectWrite) throw PlatformException(code: 'storage');
            stored[id] = args['key'] as String;
            return null;
          case 'delete':
            stored.remove(id);
            return null;
        }
        throw StateError('Unexpected native call');
      });
      final keys = PlatformAiCredentials();
      expect(await keys.contains('connection'), isTrue);
      expect(reads, 0);
      expect(await keys.read('connection'), 'saved-test-key');
      expect(await keys.read('connection'), 'saved-test-key');
      expect(reads, 1);
      await keys.write('connection', 'new-test-key');
      expect(await keys.read('connection'), 'new-test-key');
      expect(reads, 1);
      rejectWrite = true;
      await expectLater(
        keys.write('connection', 'not-saved'),
        throwsA(isA<PlatformException>()),
      );
      expect(await keys.read('connection'), 'new-test-key');
      expect(await PlatformAiCredentials().read('connection'), 'new-test-key');
      expect(reads, 2);
      await keys.delete('connection');
      expect(await keys.read('connection'), isNull);
      expect(await keys.contains('connection'), isFalse);
      expect(reads, 2);
      expect(await PlatformAiCredentials().contains('connection'), isFalse);
    },
  );

  test(
    'macOS native store persists, migrates once and removes usable secrets',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'native-ai-credentials',
      );
      try {
        final harness = File('${root.path}/main.swift');
        await File(
          'test/ai/fixtures/ai_credentials_main.swift',
        ).copy(harness.path);
        final binary = '${root.path}/check';
        final compile = await Process.run('swiftc', [
          'macos/Runner/AiCredentials.swift',
          harness.path,
          '-o',
          binary,
        ]);
        expect(compile.exitCode, 0, reason: '${compile.stderr}');
        final result = await Process.run(binary, []);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isMacOS,
  );
}
