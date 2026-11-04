import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with: flutter test tool/generate_app_icons.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render the existing leaf mark as desktop app icons', () async {
    final font = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await font.load();
    final pngs = <int, Uint8List>{};
    for (final size in [16, 32, 48, 64, 128, 256, 512, 1024]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(size / 1024);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(80, 80, 864, 864),
          const Radius.circular(194),
        ),
        Paint()..color = const Color(0xfffffcf5),
      );
      final leaf = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.eco_outlined.codePoint),
          style: const TextStyle(
            fontFamily: 'MaterialIcons',
            fontSize: 600,
            color: Color(0xff8b6245),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      leaf.paint(
        canvas,
        Offset((1024 - leaf.width) / 2, (1024 - leaf.height) / 2),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      pngs[size] = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      if (size != 48) {
        await File(
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
        ).writeAsBytes(pngs[size]!);
      }
      leaf.dispose();
      image.dispose();
      picture.dispose();
    }
    final sizes = [16, 32, 48, 64, 128, 256];
    final header = ByteData(6 + sizes.length * 16)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, sizes.length, Endian.little);
    var offset = header.lengthInBytes;
    for (var i = 0; i < sizes.length; i++) {
      final size = sizes[i];
      final at = 6 + i * 16;
      header
        ..setUint8(at, size == 256 ? 0 : size)
        ..setUint8(at + 1, size == 256 ? 0 : size)
        ..setUint16(at + 4, 1, Endian.little)
        ..setUint16(at + 6, 32, Endian.little)
        ..setUint32(at + 8, pngs[size]!.length, Endian.little)
        ..setUint32(at + 12, offset, Endian.little);
      offset += pngs[size]!.length;
    }
    await File('windows/runner/resources/app_icon.ico').writeAsBytes([
      ...header.buffer.asUint8List(),
      for (final size in sizes) ...pngs[size]!,
    ]);
  });
}
