import 'dart:ui' as ui;
import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import '../../core/typography.dart';

enum ShareCardStyle {
  paper('花影纸笺'),
  night('星夜手记'),
  mist('像素漫游'),
  sunset('胶片手记');

  const ShareCardStyle(this.label);
  final String label;
}

class ShareCardImage {
  const ShareCardImage(this.bytes, this.width, this.height, this.bodyBottom);
  final Uint8List bytes;
  final int width, height;
  final double bodyBottom;
}

abstract final class ShareCard {
  static const maxCharacters = 600;
  static String excerpt(String text, TextSelection selection) {
    if (selection.isValid &&
        !selection.isCollapsed &&
        selection.end <= text.length) {
      return text.substring(selection.start, selection.end);
    }
    return text
        .split(RegExp(r'\r\n|\r|\n'))
        .firstWhere((p) => p.trim().isNotEmpty, orElse: () => '');
  }

  static void validate(String body) {
    if (body.trim().isEmpty) throw const FormatException('请先写下想分享的片段');
    if (body.characters.length > maxCharacters) {
      throw const FormatException('片段最多 600 字，请精简后再生成卡片');
    }
  }

  static Future<ShareCardImage> render({
    required String body,
    required String work,
    required String chapter,
    String signature = '',
    ShareCardStyle style = ShareCardStyle.paper,
  }) async {
    validate(body);
    const width = 1080, margin = 96.0, contentWidth = width - margin * 2;
    final (paper, ink, muted, accent) = switch (style) {
      ShareCardStyle.paper => (
        const Color(0xfffaf5e9),
        const Color(0xff3d382e),
        const Color(0xff776850),
        const Color(0xff8b946f),
      ),
      ShareCardStyle.night => (
        const Color(0xff202a38),
        const Color(0xffedece5),
        const Color(0xffb8c2cc),
        const Color(0xffd5b985),
      ),
      ShareCardStyle.mist => (
        const Color(0xffedf4ee),
        const Color(0xff263d38),
        const Color(0xff4e665d),
        const Color(0xff497565),
      ),
      ShareCardStyle.sunset => (
        const Color(0xfff6f0e5),
        const Color(0xff382e29),
        const Color(0xff6e594a),
        const Color(0xffa96842),
      ),
    };
    TextPainter text(
      String value,
      double size,
      Color color, {
      double height = 1.5,
      double maxWidth = contentWidth,
    }) => TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: inkFontFamily,
          fontFamilyFallback: inkFontFallback,
          fontSize: size,
          height: height,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final heading = text(work, 30, ink, maxWidth: contentWidth - 220);
    final caption = text('作品摘录', 18, muted);
    final prose = text(
      body.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      40,
      ink,
      height: 1.8,
    );
    final footer = text(
      [chapter, if (signature.trim().isNotEmpty) signature.trim()].join('\n'),
      25,
      muted,
    );
    final bodyTop = margin + heading.height + 96;
    final bodyBottom = bodyTop + prose.height;
    final footerTop = bodyBottom + 72;
    final height = (footerTop + footer.height + 206).ceil();
    if (height > 8192) {
      heading.dispose();
      caption.dispose();
      prose.dispose();
      footer.dispose();
      throw const FormatException('片段分段过多，请减少空行或缩短内容后再生成');
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(paper, BlendMode.src);
    final fiber = Paint()
      ..color = ink.withValues(alpha: .035)
      ..strokeWidth = 1;
    for (var y = 18; y < height; y += 28) {
      for (var x = 16 + (y % 31); x < width; x += 59) {
        canvas.drawLine(
          Offset(x.toDouble(), y.toDouble()),
          Offset(x + 3.0, y + .8),
          fiber,
        );
      }
    }
    _paintArtwork(
      canvas,
      width.toDouble(),
      height.toDouble(),
      style,
      accent,
      paper,
    );
    caption.paint(canvas, const Offset(margin, margin - 34));
    heading.paint(canvas, const Offset(margin, margin));
    final quote = Paint()
      ..color = accent.withValues(alpha: .7)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final dx in [0.0, 14.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(margin + dx, bodyTop - 30)
          ..quadraticBezierTo(
            margin + dx - 8,
            bodyTop - 18,
            margin + dx + 1,
            bodyTop - 16,
          ),
        quote,
      );
    }
    prose.paint(canvas, Offset(margin, bodyTop));
    footer.paint(canvas, Offset(margin, footerTop));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw const FormatException('图片生成失败，请重试');
      return ShareCardImage(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        width,
        height,
        bodyBottom,
      );
    } finally {
      image.dispose();
      picture.dispose();
      heading.dispose();
      caption.dispose();
      prose.dispose();
      footer.dispose();
    }
  }

  static void _paintArtwork(
    Canvas canvas,
    double width,
    double height,
    ShareCardStyle style,
    Color accent,
    Color paper,
  ) {
    if (style == ShareCardStyle.mist) {
      _pixelArtwork(canvas, width, height);
      return;
    }
    if (style == ShareCardStyle.sunset) {
      _filmArtwork(canvas, width, height, paper);
      return;
    }
    final frame = Rect.fromLTRB(32, 32, width - 32, height - 32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(8)),
      Paint()
        ..color = accent.withValues(alpha: .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.save();
    canvas.clipRect(frame);
    final bottom = height - 168;
    switch (style) {
      case ShareCardStyle.paper:
        canvas.drawCircle(
          Offset(width - 125, 125),
          110,
          Paint()
            ..shader = ui.Gradient.radial(Offset(width - 125, 125), 110, [
              accent.withValues(alpha: .13),
              paper.withValues(alpha: 0),
            ]),
        );
        _branch(canvas, Offset(width - 260, 224), accent, .9);
        _branch(
          canvas,
          Offset(width - 150, height - 50),
          accent.withValues(alpha: .65),
          -.75,
        );
        canvas.drawPath(
          Path()
            ..moveTo(32, height - 72)
            ..quadraticBezierTo(
              width * .3,
              bottom + 30,
              width * .62,
              height - 32,
            )
            ..lineTo(32, height - 32)
            ..close(),
          Paint()..color = accent.withValues(alpha: .045),
        );
      case ShareCardStyle.night:
        final moon = Offset(width - 160, 133);
        canvas.drawCircle(
          moon,
          86,
          Paint()
            ..shader = ui.Gradient.radial(moon, 86, [
              accent.withValues(alpha: .13),
              paper.withValues(alpha: 0),
            ]),
        );
        final crescent = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: moon, radius: 39)),
          Path()..addOval(
            Rect.fromCircle(center: moon + const Offset(18, -12), radius: 37),
          ),
        );
        canvas.drawPath(
          crescent,
          Paint()..color = accent.withValues(alpha: .82),
        );
        for (final p in [
          Offset(width - 245, 92),
          Offset(width - 85, 185),
          Offset(width - 270, 205),
        ]) {
          _star(canvas, p, 5, accent);
        }
        final points = [
          Offset(110, height - 95),
          Offset(215, height - 127),
          Offset(322, height - 79),
          Offset(420, height - 115),
        ];
        final constellation = Path()..moveTo(points.first.dx, points.first.dy);
        for (final p in points.skip(1)) {
          constellation.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          constellation,
          Paint()
            ..color = accent.withValues(alpha: .25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        for (final p in points) {
          _star(canvas, p, 3.5, accent.withValues(alpha: .65));
        }
        _star(
          canvas,
          Offset(width - 130, height - 96),
          5,
          accent.withValues(alpha: .7),
        );
      case ShareCardStyle.mist:
      case ShareCardStyle.sunset:
        break;
    }
    canvas.restore();
  }

  static void _branch(Canvas canvas, Offset origin, Color color, double scale) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale, scale.abs());
    final stem = Path()
      ..moveTo(0, 0)
      ..cubicTo(75, -50, 92, -102, 129, -174);
    canvas.drawPath(
      stem,
      Paint()
        ..color = color.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    for (final leaf in [
      (26.0, -23.0, -1.0),
      (46.0, -43.0, 1.0),
      (64.0, -67.0, -1.0),
      (81.0, -94.0, 1.0),
      (98.0, -126.0, -1.0),
      (117.0, -151.0, 1.0),
    ]) {
      final (x, y, d) = leaf;
      final path = Path()
        ..moveTo(x, y)
        ..cubicTo(x + d * 45, y - 4, x + d * 48, y - 29, x + d * 48, y - 35)
        ..cubicTo(x + d * 18, y - 32, x + d * 4, y - 19, x, y)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .2));
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(x + d * 25, y - 15, x + d * 41, y - 29),
        Paint()
          ..color = color.withValues(alpha: .48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
  }

  static void _star(Canvas canvas, Offset p, double radius, Color color) {
    final path = Path()
      ..moveTo(p.dx, p.dy - radius)
      ..quadraticBezierTo(
        p.dx + radius * .2,
        p.dy - radius * .2,
        p.dx + radius,
        p.dy,
      )
      ..quadraticBezierTo(
        p.dx + radius * .2,
        p.dy + radius * .2,
        p.dx,
        p.dy + radius,
      )
      ..quadraticBezierTo(
        p.dx - radius * .2,
        p.dy + radius * .2,
        p.dx - radius,
        p.dy,
      )
      ..quadraticBezierTo(
        p.dx - radius * .2,
        p.dy - radius * .2,
        p.dx,
        p.dy - radius,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  static void _pixelArtwork(Canvas canvas, double width, double height) {
    const dark = Color(0xff35594e);
    const green = Color(0xff7ea78a);
    const sky = Color(0xffc5dbce);
    void block(double x, double y, double w, double h, Color color) =>
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = color);

    // A tiny window above the prose; all scene edges follow an 8px grid.
    final x = width - 272;
    block(x + 8, 64, 184, 152, const Color(0xffd0ded0));
    block(x, 56, 184, 152, dark);
    block(x + 8, 64, 168, 136, sky);
    block(x + 112, 80, 24, 24, const Color(0xfff4d891));
    block(x + 24, 88, 40, 8, const Color(0xfff4f5df));
    block(x + 16, 96, 64, 8, const Color(0xfff4f5df));
    for (var i = 0; i < 7; i++) {
      block(x + 8 + i * 24, 152 - (i % 3) * 16, 24, 48 + (i % 3) * 16, green);
    }
    block(x + 8, 176, 168, 24, const Color(0xff557f69));
    block(x + 88, 64, 8, 136, dark);
    block(x + 8, 128, 168, 8, dark);
    block(x - 8, 208, 200, 8, dark);

    // A low panorama sits entirely below the chapter and signature.
    final y = height - 152;
    block(64, y, width - 128, 104, sky);
    for (var i = 0; i < 22; i++) {
      block(
        64 + i * 44,
        y + 40 - (i % 4) * 8,
        i == 21 ? 28 : 44,
        64 + (i % 4) * 8,
        green,
      );
    }
    block(64, y + 80, width - 128, 24, const Color(0xff557f69));
    block(64, y + 104, width - 128, 8, dark);
    // A lamplit cottage, stepping stones, and a small wandering cat.
    block(width - 280, y + 24, 64, 56, const Color(0xfff0dfb5));
    block(width - 288, y + 16, 80, 16, dark);
    block(width - 280, y + 8, 64, 8, dark);
    block(width - 272, y, 48, 8, dark);
    block(width - 264, y + 40, 16, 16, const Color(0xffa96842));
    block(width - 240, y + 48, 16, 32, dark);
    for (var i = 0; i < 4; i++) {
      block(width - 244 - i * 32, y + 88, 16, 8, const Color(0xffe1d8b6));
    }
    block(208, y + 64, 24, 16, dark);
    block(224, y + 56, 16, 16, dark);
    block(224, y + 48, 4, 8, dark);
    block(236, y + 48, 4, 8, dark);
    block(200, y + 56, 8, 16, dark);
    for (final corner in [const Offset(40, 40), Offset(width - 56, 40)]) {
      block(corner.dx, corner.dy, 16, 8, dark);
      block(corner.dx, corner.dy, 8, 16, dark);
    }
  }

  static void _filmArtwork(
    Canvas canvas,
    double width,
    double height,
    Color paper,
  ) {
    const film = Color(0xff49372c);
    const sand = Color(0xffd6bb94);
    final paint = Paint();
    // Punched film rails stay outside the 96px text margins.
    for (final x in [32.0, width - 62]) {
      canvas.drawRect(
        Rect.fromLTWH(x, 32, 30, height - 64),
        paint..color = film,
      );
      for (var y = 48.0; y < height - 48; y += 36) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 9, y, 12, 20),
            const Radius.circular(2),
          ),
          paint..color = paper,
        );
      }
    }
    // A warm instant photograph, secured with translucent paper tape.
    canvas.save();
    canvas.translate(width - 190, 137);
    canvas.rotate(.075);
    canvas.drawRect(
      const Rect.fromLTWH(-89, -78, 184, 168),
      paint..color = const Color(0xffddd1bb),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-94, -83, 184, 168),
      paint..color = const Color(0xfffffbf2),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-82, -71, 160, 120),
      paint..color = sand,
    );
    canvas.drawCircle(
      const Offset(28, -33),
      23,
      paint..color = const Color(0xffedd99d),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-82, 2)
        ..lineTo(-40, -24)
        ..lineTo(-8, 6)
        ..lineTo(32, -12)
        ..lineTo(78, 15)
        ..lineTo(78, 49)
        ..lineTo(-82, 49)
        ..close(),
      paint..color = const Color(0xff9b8065),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-82, 28)
        ..quadraticBezierTo(-10, -6, 78, 33)
        ..lineTo(78, 49)
        ..lineTo(-82, 49)
        ..close(),
      paint..color = const Color(0xff665f4e),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-33, -92, 76, 22),
      paint..color = const Color(0xbbc2b28b),
    );
    canvas.restore();

    final y = height - 146;
    // A horizontal contact sheet and a torn ticket create a separate footer rhythm.
    canvas.drawRect(Rect.fromLTWH(96, y, 458, 98), paint..color = film);
    for (var i = 0; i < 3; i++) {
      final x = 108.0 + i * 148;
      canvas.drawRect(Rect.fromLTWH(x, y + 14, 138, 70), paint..color = sand);
      canvas.drawCircle(
        Offset(x + 97, y + 36),
        14,
        paint..color = const Color(0xffedd99d),
      );
      canvas.drawPath(
        Path()
          ..moveTo(x, y + 70)
          ..lineTo(x + 40, y + 38 + i * 6)
          ..lineTo(x + 80, y + 64)
          ..lineTo(x + 138, y + 42)
          ..lineTo(x + 138, y + 84)
          ..lineTo(x, y + 84)
          ..close(),
        paint..color = const Color(0xff82795d),
      );
      for (final dy in [4.0, 88.0]) {
        for (var j = 0; j < 6; j++) {
          canvas.drawRect(
            Rect.fromLTWH(x + j * 24, y + dy, 10, 6),
            paint..color = paper,
          );
        }
      }
    }
    final ticket = Rect.fromLTWH(width - 356, y + 10, 246, 76);
    canvas.drawRect(ticket, paint..color = const Color(0xffe7dac1));
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
        Offset(ticket.left, ticket.top + 7 + i * 15),
        4,
        paint..color = paper,
      );
      canvas.drawCircle(
        Offset(ticket.right, ticket.top + 7 + i * 15),
        4,
        paint..color = paper,
      );
    }
    for (var i = 0; i < 6; i++) {
      canvas.drawLine(
        Offset(ticket.left + 50, ticket.top + 6 + i * 11),
        Offset(ticket.left + 50, ticket.top + 11 + i * 11),
        paint
          ..color = const Color(0xffb7a384)
          ..strokeWidth = 1,
      );
    }
    canvas.drawCircle(
      Offset(ticket.right - 50, ticket.center.dy),
      23,
      paint
        ..color = const Color(0xffa96842)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(Offset(ticket.right - 50, ticket.center.dy), 17, paint);
    canvas.drawLine(
      Offset(ticket.left + 72, ticket.top + 28),
      Offset(ticket.right - 92, ticket.top + 28),
      paint,
    );
    canvas.drawLine(
      Offset(ticket.left + 72, ticket.top + 46),
      Offset(ticket.right - 92, ticket.top + 46),
      paint,
    );
  }
}
