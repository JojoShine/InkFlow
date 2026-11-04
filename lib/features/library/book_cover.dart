import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/platform/desktop_services.dart';
import '../appearance/theme_presets.dart';
import '../preferences/device_preferences.dart';

class BookCover extends StatefulWidget {
  const BookCover({
    super.key,
    required this.entry,
    required this.services,
    required this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });
  final RecentWork entry;
  final DesktopServices services;
  final double width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  State<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<BookCover> {
  Future<Directory>? _root;

  void _resolve() {
    _root = widget.entry.coverFile == null
        ? null
        : widget.services.resolveDirectory(
            widget.entry.path,
            widget.entry.bookmark,
          );
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path ||
        oldWidget.entry.bookmark != widget.entry.bookmark ||
        oldWidget.entry.coverFile != widget.entry.coverFile) {
      _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    final shade = widget.entry.workId.codeUnits.fold(0, (a, b) => a + b) % 3;
    final placeholder = ColoredBox(
      color: Color.lerp(colors.paper, colors.accent, .05 + shade * .03)!,
      child: CustomPaint(
        painter: _CoverDetail(colors.accent),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.width * .12,
              vertical: 10,
            ),
            child: Text(
              widget.entry.title,
              key: ValueKey('cover-title-${widget.entry.workId}'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.ink,
                fontSize: (widget.width * .13).clamp(8, 12),
                letterSpacing: 0,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.width,
        height: widget.height ?? widget.width * 1.5,
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: _root == null
              ? placeholder
              : FutureBuilder<Directory>(
                  future: _root,
                  builder: (_, snapshot) => snapshot.hasData
                      ? Image.file(
                          File(
                            '${snapshot.data!.path}/${widget.entry.coverFile}',
                          ),
                          fit: BoxFit.cover,
                          cacheWidth:
                              (widget.width *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round()
                                  .clamp(1, 600),
                          errorBuilder: (_, error, stack) => placeholder,
                        )
                      : placeholder,
                ),
        ),
      ),
    );
  }
}

class _CoverDetail extends CustomPainter {
  const _CoverDetail(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grain = Paint()
      ..color = color.withValues(alpha: .045)
      ..strokeWidth = .6;
    for (var i = 0; i < 48; i++) {
      final x = (i * 37 % 101) / 101 * size.width;
      final y = (i * 29 % 149) / 149 * size.height;
      canvas.drawLine(Offset(x, y), Offset(x + 1.5, y + .25), grain);
    }
    final line = Paint()
      ..color = color.withValues(alpha: .22)
      ..strokeWidth = .6
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTWH(7, 7, size.width - 14, size.height - 14),
      line,
    );
    canvas.drawLine(const Offset(3, 0), Offset(3, size.height), line);
    canvas.drawLine(
      Offset(size.width * .4, size.height - 17),
      Offset(size.width * .6, size.height - 17),
      line,
    );
  }

  @override
  bool shouldRepaint(_CoverDetail oldDelegate) => color != oldDelegate.color;
}
