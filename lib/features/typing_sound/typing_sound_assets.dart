import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'typing_sound_settings.dart';

final _sounds = <String, Future<ByteData>>{};

Future<Uint8List?> typingSoundBytes(TypingSoundSettings settings) async {
  final asset = settings.preset.asset;
  if (asset == null || settings.volume == 0) return null;
  final original = await _sounds.putIfAbsent(
    asset,
    () => rootBundle.load(asset),
  );
  final bytes = Uint8List.fromList(
    original.buffer.asUint8List(original.offsetInBytes, original.lengthInBytes),
  );
  final wave = ByteData.sublistView(bytes);
  // Bundled sounds are mono, 16-bit PCM with a 44-byte RIFF header.
  for (var offset = 44; offset + 1 < bytes.length; offset += 2) {
    wave.setInt16(
      offset,
      (wave.getInt16(offset, Endian.little) * settings.volume).round(),
      Endian.little,
    );
  }
  return bytes;
}
