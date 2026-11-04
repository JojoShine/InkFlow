import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Keep imported covers self-contained and small enough for the bookshelf.
Future<Uint8List> normalizeCover(List<int> bytes) async {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('请选择小于 20 MB 的封面图片');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    Uint8List.fromList(bytes),
  );
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.min(
      1.0,
      math.min(800 / descriptor.width, 1200 / descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const FormatException('无法读取封面图片');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    throw const FormatException('无法读取图片，请选择 PNG、JPEG 或 WebP 图片');
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
