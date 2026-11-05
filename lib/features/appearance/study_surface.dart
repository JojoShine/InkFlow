import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'appearance_settings.dart';

class StudySurface extends StatelessWidget {
  const StudySurface({
    super.key,
    required this.color,
    required this.settings,
    required this.child,
    this.texture,
  });
  final Color color;
  final AppearanceSettings settings;
  final Widget child;
  final StudyTexture? texture;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _StudyGrain(
                    texture ?? settings.texture,
                    settings.isNight,
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

class _StudyGrain extends CustomPainter {
  const _StudyGrain(this.texture, this.isNight);
  final StudyTexture texture;
  final bool isNight;
  static final _fibers = (() {
    final random = math.Random(31);
    return List.generate(72, (_) {
      final start = Offset(random.nextDouble() * 90, random.nextDouble() * 90);
      return (
        start,
        start + Offset(.5 + random.nextDouble() * 3, random.nextDouble() * .6),
      );
    });
  })();

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == StudyTexture.none) return;
    final path = Path();
    for (var y = 0.0; y < size.height; y += 96) {
      for (var x = 0.0; x < size.width; x += 96) {
        for (final (start, end) in _fibers) {
          path
            ..moveTo(x + start.dx, y + start.dy)
            ..lineTo(x + end.dx, y + end.dy);
          if (texture == StudyTexture.linen) {
            path
              ..moveTo(x + start.dy, y + start.dx)
              ..lineTo(x + end.dy, y + end.dx);
          }
        }
      }
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..color = (isNight ? Colors.white : Colors.black).withValues(
          alpha: isNight ? .025 : .035,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StudyGrain oldDelegate) =>
      oldDelegate.texture != texture || oldDelegate.isNight != isNight;
}
