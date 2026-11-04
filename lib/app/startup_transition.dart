import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../features/appearance/theme_presets.dart';

class StartupTransition extends StatefulWidget {
  const StartupTransition({
    super.key,
    required this.ready,
    required this.child,
    this.animationsEnabled = true,
  });
  final bool ready;
  final bool animationsEnabled;
  final Widget child;

  @override
  State<StartupTransition> createState() => _StartupTransitionState();
}

class _StartupTransitionState extends State<StartupTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _stroke;
  late bool _showIntro;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _showIntro = !widget.ready;
    _stroke =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              widget.ready &&
              _showIntro) {
            setState(() => _showIntro = false);
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) || !widget.animationsEnabled;
    if (_reduceMotion || !_showIntro) {
      _stroke.value = 1;
    } else if (!_stroke.isAnimating && !_stroke.isCompleted) {
      _stroke.forward();
    }
  }

  @override
  void didUpdateWidget(StartupTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animationsEnabled) _stroke.value = 1;
    if (widget.ready &&
        (_stroke.isCompleted || !widget.animationsEnabled || _reduceMotion)) {
      _showIntro = false;
    }
  }

  @override
  void dispose() {
    _stroke.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showIntro) return widget.child;
    final colors = InkPalette.of(context);
    return Semantics(
      label: 'InkFlow 正在打开书房',
      child: Material(
        color: colors.background,
        child: Center(
          child: RepaintBoundary(
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: const Size(240, 108),
                    painter: _FeatherStroke(_stroke, colors.accent),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'InkFlow',
                    style: TextStyle(color: colors.ink, fontSize: 23),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatherStroke extends CustomPainter {
  _FeatherStroke(this.progress, this.color) : super(repaint: progress);
  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOutCubic.transform(progress.value);
    final line = Path()
      ..moveTo(40, 82)
      ..cubicTo(85, 88, 149, 72, 193, 80);
    final metric = line.computeMetrics().first;
    final length = metric.length * t;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(metric.extractPath(0, length), pen);
    final tip =
        metric.getTangentForOffset(length)?.position ?? const Offset(40, 82);
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(-0.12 + math.sin(t * math.pi) * 0.09);
    final feather = Path()
      ..moveTo(0, 0)
      ..cubicTo(1, -29, 21, -60, 48, -66)
      ..cubicTo(48, -39, 30, -15, 0, 0)
      ..moveTo(0, 0)
      ..quadraticBezierTo(19, -26, 43, -60)
      ..moveTo(13, -20)
      ..lineTo(11, -38)
      ..moveTo(24, -35)
      ..lineTo(24, -52)
      ..moveTo(15, -22)
      ..lineTo(30, -24)
      ..moveTo(28, -40)
      ..lineTo(41, -42);
    canvas.drawPath(feather, pen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FeatherStroke oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}
