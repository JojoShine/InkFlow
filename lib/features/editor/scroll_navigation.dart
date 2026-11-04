import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../app/ink_icons.dart';

class EditorScrollPosition {
  const EditorScrollPosition({
    this.offset = 0,
    this.maxExtent = 0,
    this.viewport = 0,
  });
  final double offset, maxExtent, viewport;
  bool get scrollable => maxExtent > 1;
  bool get atBottom =>
      scrollable &&
      offset > 1 &&
      maxExtent - offset <= math.max(2, math.min(48, viewport * .06));
}

class ScrollNavigation extends StatefulWidget {
  static const width = 44.0;
  const ScrollNavigation({
    super.key,
    required this.position,
    required this.onScrollTo,
    required this.color,
  });
  final ValueListenable<EditorScrollPosition> position;
  final ValueChanged<double> onScrollTo;
  final Color color;
  @override
  State<ScrollNavigation> createState() => _ScrollNavigationState();
}

class _ScrollNavigationState extends State<ScrollNavigation> {
  Timer? _hide;
  bool _visible = false, _hover = false, _dragging = false;
  double _startY = 0, _startOffset = 0;
  double? _displayOffset;
  double _knownMaxExtent = 0;

  @override
  void initState() {
    super.initState();
    _knownMaxExtent = widget.position.value.maxExtent;
    widget.position.addListener(_changed);
  }

  @override
  void didUpdateWidget(ScrollNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_changed);
      widget.position.addListener(_changed);
    }
  }

  void _changed() {
    final p = widget.position.value;
    if (!_dragging ||
        p.maxExtent != _knownMaxExtent ||
        (_displayOffset != null && (p.offset - _displayOffset!).abs() < 2)) {
      _displayOffset = null;
    }
    _knownMaxExtent = p.maxExtent;
    _show();
  }

  void _show() {
    _hide?.cancel();
    if (mounted) setState(() => _visible = true);
    if (!_hover && !_dragging) {
      _hide = Timer(const Duration(milliseconds: 1000), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  void _scroll(double offset) {
    final target = offset
        .clamp(0.0, widget.position.value.maxExtent)
        .toDouble();
    setState(() => _displayOffset = target);
    widget.onScrollTo(target);
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.position.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actual = widget.position.value;
    final p = EditorScrollPosition(
      offset: _displayOffset ?? actual.offset,
      maxExtent: actual.maxExtent,
      viewport: actual.viewport,
    );
    if (!p.scrollable) return const SizedBox.expand();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        _hover = true;
        _show();
      },
      onExit: (_) {
        _hover = false;
        _show();
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            GestureBinding.instance.pointerSignalResolver.register(
              event,
              (_) => _scroll(p.offset + event.scrollDelta.dy),
            );
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final track = math.max(0.0, constraints.maxHeight - 60);
            final thumb = (track * p.viewport / (p.viewport + p.maxExtent))
                .clamp(math.min(28.0, track), track)
                .toDouble();
            final travel = track - thumb;
            final top = travel <= 0
                ? 0.0
                : p.offset.clamp(0, p.maxExtent) / p.maxExtent * travel;
            return Stack(
              children: [
                Positioned(
                  top: 10,
                  bottom: 50,
                  right: 0,
                  left: 0,
                  child: Semantics(
                    label: '正文滚动位置',
                    value: '${(p.offset / p.maxExtent * 100).round()}%',
                    increasedValue:
                        '${((p.offset + p.viewport * .8).clamp(0, p.maxExtent) / p.maxExtent * 100).round()}%',
                    decreasedValue:
                        '${((p.offset - p.viewport * .8).clamp(0, p.maxExtent) / p.maxExtent * 100).round()}%',
                    onIncrease: () => _scroll(p.offset + p.viewport * .8),
                    onDecrease: () => _scroll(p.offset - p.viewport * .8),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        if (details.localPosition.dy >= top &&
                            details.localPosition.dy <= top + thumb) {
                          return;
                        }
                        if (travel > 0) {
                          _scroll(
                            (details.localPosition.dy - thumb / 2) /
                                travel *
                                p.maxExtent,
                          );
                        }
                      },
                      onVerticalDragStart: (details) {
                        _dragging = true;
                        _startY = details.localPosition.dy;
                        _startOffset =
                            _displayOffset ?? widget.position.value.offset;
                        _show();
                      },
                      onVerticalDragUpdate: (details) {
                        if (travel > 0) {
                          _scroll(
                            _startOffset +
                                (details.localPosition.dy - _startY) /
                                    travel *
                                    p.maxExtent,
                          );
                        }
                      },
                      onVerticalDragEnd: (_) {
                        _dragging = false;
                        _show();
                      },
                      onVerticalDragCancel: () {
                        _dragging = false;
                        _show();
                      },
                      child: AnimatedOpacity(
                        key: const ValueKey('scroll-thumb-opacity'),
                        opacity: _visible ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Stack(
                          children: [
                            Positioned(
                              top: top,
                              right: 3,
                              width: _hover || _dragging ? 6 : 4,
                              height: thumb,
                              child: DecoratedBox(
                                key: const ValueKey('scroll-thumb'),
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(
                                    alpha: _hover || _dragging ? .65 : .4,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (p.atBottom)
                  Positioned(
                    bottom: 14,
                    right: 16,
                    width: 28,
                    height: 28,
                    child: Tooltip(
                      message: '返回顶部',
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        style: IconButton.styleFrom(
                          foregroundColor: widget.color.withValues(alpha: .65),
                          backgroundColor: Colors.transparent,
                          hoverColor: widget.color.withValues(alpha: .07),
                          highlightColor: widget.color.withValues(alpha: .12),
                          side: BorderSide.none,
                          shape: const CircleBorder(),
                        ),
                        onPressed: () => _scroll(0),
                        icon: const Icon(InkIcons.arrowUp, size: 14),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
