import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/preferences/device_preferences.dart';
import 'package:inkflow/features/typing_sound/typing_sound_settings.dart';
import 'package:inkflow/features/typing_sound/typing_sound_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'old preferences default to silent and sound settings persist independently',
    () {
      final legacy = const DevicePreferences().toJson()..remove('typingSound');
      expect(
        DevicePreferences.fromJson(legacy).typingSound.preset,
        TypingSoundPreset.off,
      );
      final preferences = DevicePreferences.fromJson(legacy).copyWith(
        typingSound: const TypingSoundSettings(
          preset: TypingSoundPreset.typewriter,
          volume: .4,
        ),
        libraryRootPath: '/library',
      );
      final restored = DevicePreferences.fromJson(preferences.toJson());
      expect(restored.typingSound.preset, TypingSoundPreset.typewriter);
      expect(restored.typingSound.volume, .4);
      expect(
        restored
            .copyWith(layout: restored.layout.copyWith(fontSize: 24))
            .typingSound
            .volume,
        .4,
      );
      expect(restored.libraryRootPath, '/library');
    },
  );
  test('each sound is bundled as a short uncompressed PCM wave', () async {
    for (final preset in TypingSoundPreset.values.where(
      (p) => p != TypingSoundPreset.off,
    )) {
      final bytes = await rootBundle.load(preset.asset!);
      expect(String.fromCharCodes(bytes.buffer.asUint8List(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.buffer.asUint8List(8, 4)), 'WAVE');
      expect(bytes.getUint16(20, Endian.little), 1);
      expect(bytes.getUint16(34, Endian.little), 16);
      expect(bytes.lengthInBytes, lessThan(16000));
    }
  });
  test(
    'volume scales PCM samples without modifying the bundled header or original bytes',
    () async {
      expect(await typingSoundBytes(const TypingSoundSettings()), isNull);
      final full = await typingSoundBytes(
        const TypingSoundSettings(preset: TypingSoundPreset.soft, volume: 1),
      );
      final half = await typingSoundBytes(
        const TypingSoundSettings(preset: TypingSoundPreset.soft, volume: .5),
      );
      expect(half!.sublist(0, 44), full!.sublist(0, 44));
      final a = ByteData.sublistView(full), b = ByteData.sublistView(half);
      for (var i = 44; i < full.length; i += 2) {
        expect(
          b.getInt16(i, Endian.little),
          (a.getInt16(i, Endian.little) * .5).round(),
        );
      }
    },
  );
}
