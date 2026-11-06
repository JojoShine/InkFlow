import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/typography.dart';
import '../typing_sound/typing_sound_settings.dart';
import '../typing_sound/typing_sound_assets.dart';

import 'editor_session.dart';
import 'scroll_navigation.dart';

class NovelEditor extends StatefulWidget {
  const NovelEditor({
    super.key,
    required this.session,
    required this.layout,
    required this.textColor,
    required this.backgroundColor,
    this.onSave,
    this.onExitFocus,
    this.onFileAction,
    this.overlayOpen = false,
    this.focusMode = false,
    this.typingSound = const TypingSoundSettings(),
  });

  final EditorSession session;
  final EditorLayoutSettings layout;
  final Color textColor;
  final Color backgroundColor;
  final Future<void> Function()? onSave;
  final VoidCallback? onExitFocus;
  final Future<void> Function(String)? onFileAction;
  final bool overlayOpen;
  final bool focusMode;
  final TypingSoundSettings typingSound;

  @override
  State<NovelEditor> createState() => _NovelEditorState();
}

class _NovelEditorState extends State<NovelEditor> with WidgetsBindingObserver {
  MethodChannel? _channel;
  bool _receiving = false;
  final _windowsHost = GlobalKey();
  final _fallbackFocus = FocusNode();
  bool _windowsReady = false;
  ui.Image? _snapshot;
  bool _capturingSnapshot = false;
  bool _snapshotFailed = false;
  int _snapshotGeneration = 0;
  bool _snapshotAgain = false;

  Future<void> _captureSnapshot() async {
    if (_capturingSnapshot) {
      _snapshotAgain = true;
      return;
    }
    if (!_windowsReady || _windowsVisible || !mounted) return;
    _capturingSnapshot = true;
    final request = ++_snapshotGeneration;
    final documentGeneration = widget.session.documentGeneration;
    try {
      final value = await _channel!
          .invokeMapMethod<Object?, Object?>('snapshot', {
            'documentId': widget.session.chapterId ?? 'probe',
            'documentGeneration': documentGeneration,
          });
      if (value == null) throw const FormatException('正文预览暂不可用');
      final width = value['width'] as int, height = value['height'] as int;
      final bytes = value['pixels'] as Uint8List;
      if (width <= 0 ||
          height <= 0 ||
          width * height > 16777216 ||
          bytes.length != width * height * 4) {
        throw const FormatException('正文预览数据不完整');
      }
      final ready = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        width,
        height,
        ui.PixelFormat.bgra8888,
        ready.complete,
        rowBytes: value['rowBytes'] as int,
      );
      final image = await ready.future;
      if (!mounted ||
          request != _snapshotGeneration ||
          _windowsVisible ||
          widget.session.documentGeneration != documentGeneration) {
        image.dispose();
        return;
      }
      final previous = _snapshot;
      setState(() {
        _snapshot = image;
        _snapshotFailed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous?.dispose();
        if (mounted) _syncWindowsBounds();
      });
    } catch (_) {
      if (mounted && request == _snapshotGeneration) {
        setState(() => _snapshotFailed = true);
      }
    } finally {
      _capturingSnapshot = false;
      if (_snapshotAgain && mounted && !_windowsVisible) {
        _snapshotAgain = false;
        unawaited(_captureSnapshot());
      }
    }
  }

  bool _windowsVisible = true;
  Rect? _lastBounds;
  bool? _lastVisible;
  bool _macInteractive = true;
  bool? _lastMacInteractive;
  int _soundGeneration = 0;
  static const _gutter = ScrollNavigation.width;
  final _scrollPosition = ValueNotifier(const EditorScrollPosition());
  late final ScrollController _fallbackScroll;
  int _scrollGeneration = -1;
  bool _fallbackMetricsPending = false;

  Map<String, Object> get _configuration => {
    ...widget.layout.toJson(),
    'scrollbarGutter': _gutter,
    'textColor': widget.textColor.toARGB32(),
    'backgroundColor': widget.backgroundColor.toARGB32(),
  };

  Map<String, Object> get _document => {
    'documentId': widget.session.chapterId ?? 'probe',
    'documentGeneration': widget.session.documentGeneration,
    'text': widget.session.controller.text,
    'selectionBase': widget.session.controller.selection.baseOffset,
    'selectionExtent': widget.session.controller.selection.extentOffset,
    'scrollOffset': widget.session.scrollOffset,
  };

  @override
  void initState() {
    super.initState();
    _scrollGeneration = widget.session.documentGeneration;
    _fallbackScroll = ScrollController(
      initialScrollOffset: widget.session.scrollOffset,
    )..addListener(_scheduleFallbackMetrics);
    widget.session.addListener(_sessionChanged);
    widget.session.controller.addListener(_sendDocument);
    if (defaultTargetPlatform == TargetPlatform.windows) {
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect(-1);
      });
    }
  }

  Future<void> _connect(int id) async {
    _channel = MethodChannel(
      id == -1 ? 'inkflow/editor/windows' : 'inkflow/editor/$id',
    );
    _channel!.setMethodCallHandler((call) async {
      if ((call.method == 'changed' || call.method == 'selection') && mounted) {
        _receiving = true;
        try {
          if (call.method == 'selection') {
            widget.session.applyNativeSelection(call.arguments as Map);
          } else {
            widget.session.applyNativeValue(call.arguments as Map);
          }
        } finally {
          _receiving = false;
        }
      } else if (call.method == 'scrolled' && mounted) {
        final values = call.arguments;
        if (values is Map &&
            values['documentId'] == (widget.session.chapterId ?? 'probe') &&
            values['documentGeneration'] == widget.session.documentGeneration) {
          final position = EditorScrollPosition(
            offset: (values['offset'] as num).toDouble(),
            maxExtent: (values['maxExtent'] as num).toDouble(),
            viewport: (values['viewport'] as num).toDouble(),
          );
          widget.session.scrollOffset = position.offset;
          _scrollPosition.value = position;
        }
      } else if (call.method == 'composition' && mounted) {
        widget.session.nativeComposing = call.arguments as bool;
      } else if (call.method == 'saveRequested' && mounted) {
        if (widget.onSave != null) {
          await widget.onSave!();
        } else {
          await widget.session.flush();
        }
      } else if (call.method == 'exitFocus' && mounted) {
        widget.onExitFocus?.call();
      } else if (call.method == 'fileAction' && mounted) {
        await widget.onFileAction?.call(call.arguments as String);
      }
    });
    widget.session.synchronizeNative = (commit) async {
      final session = widget.session,
          generation = widget.session.documentGeneration;
      final value = await _channel!.invokeMapMethod<Object?, Object?>(
        commit ? 'commitComposition' : 'getState',
      );
      if (!mounted ||
          !identical(session, widget.session) ||
          session.documentGeneration != generation) {
        throw const FormatException('章节已变化，请重新打开操作窗口');
      }
      if (value != null) {
        _receiving = true;
        try {
          widget.session.applyNativeValue(value);
        } finally {
          _receiving = false;
        }
      }
    };
    widget.session.nativeLockForUpdate = (locked) async {
      final session = widget.session;
      final generation = session.documentGeneration;
      final value = await _channel!.invokeMapMethod<Object?, Object?>(
        'lockForUpdate',
        locked,
      );
      if (!mounted ||
          !identical(session, widget.session) ||
          generation != session.documentGeneration ||
          value == null ||
          value['isUpdateLocked'] != locked) {
        throw const FormatException('编辑器锁定状态未确认，请稍后重试');
      }
      _receiving = true;
      try {
        session.applyNativeValue(value);
      } finally {
        _receiving = false;
      }
    };
    widget.session.applyNativeEdit = (source, range, replacement) async {
      final session = widget.session,
          generation = widget.session.documentGeneration;
      final state = await _channel!
          .invokeMapMethod<Object?, Object?>('replaceRange', {
            'documentId': widget.session.chapterId ?? 'probe',
            'expectedText': source,
            'rangeStart': range.start,
            'rangeEnd': range.end,
            'replacement': replacement,
          });
      if (state == null ||
          !mounted ||
          !identical(session, widget.session) ||
          session.documentGeneration != generation ||
          session.controller.text != source) {
        throw const FormatException('编辑器暂不可用，请重新打开章节');
      }
      _receiving = true;
      try {
        widget.session.applyNativeValue(state);
      } finally {
        _receiving = false;
      }
    };
    if (id == -1) {
      final render = _windowsHost.currentContext?.findRenderObject();
      final initialBounds = <String, Object>{};
      if (render is RenderBox && render.hasSize) {
        final origin = render.localToGlobal(Offset.zero);
        final scale = View.of(context).devicePixelRatio;
        initialBounds.addAll({
          'x': (origin.dx * scale).round(),
          'y': (origin.dy * scale).round(),
          'width': (render.size.width * scale).round(),
          'height': (render.size.height * scale).round(),
          'scale': scale,
        });
      }
      await _channel!.invokeMethod<void>('create', {
        ..._configuration,
        ..._document,
        ...initialBounds,
      });
      if (!mounted) {
        await _channel!.invokeMethod<void>('destroy');
        return;
      }
      _windowsReady = true;
      _syncWindowsBounds();
    }
    await _channel!.invokeMethod('configure', _configuration);
    await _channel!.invokeMethod('load', _document);
    if (widget.session.isUpdateLocked) {
      await widget.session.nativeLockForUpdate!(true);
    }
    widget.session.previewTypingSound = () => _configureSound(preview: true);
    await _configureSound();
    if (defaultTargetPlatform == TargetPlatform.macOS) _syncMacInteraction();
    if (widget.focusMode) _focusEditor();
  }

  Future<void> _configureSound({bool preview = false}) async {
    final generation = ++_soundGeneration;
    final bytes = await typingSoundBytes(widget.typingSound);
    if (!mounted || generation != _soundGeneration) return;
    await _channel?.invokeMethod<void>('sound', {
      'bytes': bytes,
      'preview': preview,
    });
  }

  void _syncMacInteraction() {
    if (!mounted ||
        _channel == null ||
        _lastMacInteractive == _macInteractive) {
      return;
    }
    _lastMacInteractive = _macInteractive;
    _channel!.invokeMethod<void>('interactive', _macInteractive);
  }

  void _focusEditor() {
    if (!mounted) return;
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows) {
      _channel?.invokeMethod<void>('focus');
    } else {
      _fallbackFocus.requestFocus();
    }
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  void _sendDocument() {
    if (_scrollGeneration != widget.session.documentGeneration) {
      _scrollGeneration = widget.session.documentGeneration;
      _scrollPosition.value = const EditorScrollPosition();
      if (_fallbackScroll.hasClients) {
        _fallbackScroll.jumpTo(widget.session.scrollOffset);
      }
    }
    if (!_receiving) _channel?.invokeMethod<void>('load', _document);
  }

  void _scheduleFallbackMetrics() {
    if (_fallbackMetricsPending) return;
    _fallbackMetricsPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fallbackMetricsPending = false;
      if (!mounted ||
          !_fallbackScroll.hasClients ||
          !_fallbackScroll.position.hasContentDimensions) {
        return;
      }
      final p = _fallbackScroll.position;
      widget.session.scrollOffset = p.pixels;
      _scrollPosition.value = EditorScrollPosition(
        offset: p.pixels,
        maxExtent: p.maxScrollExtent,
        viewport: p.viewportDimension,
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _scrollTo(double offset) {
    if (widget.overlayOpen) return;
    if (_channel != null) {
      _channel!.invokeMethod<void>('scrollTo', {
        'documentId': widget.session.chapterId ?? 'probe',
        'documentGeneration': widget.session.documentGeneration,
        'offset': offset,
      });
    } else if (_fallbackScroll.hasClients) {
      _fallbackScroll.jumpTo(
        offset.clamp(0, _fallbackScroll.position.maxScrollExtent),
      );
    }
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncWindowsBounds();
    });
  }

  void _syncWindowsBounds() {
    if (!_windowsReady || !mounted) return;
    final render = _windowsHost.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize || !render.attached) return;
    final origin = render.localToGlobal(Offset.zero);
    final scale = View.of(context).devicePixelRatio;
    final bounds = Rect.fromLTWH(
      origin.dx * scale,
      origin.dy * scale,
      render.size.width * scale,
      render.size.height * scale,
    );
    if (_lastBounds != bounds) {
      final previousBounds = _lastBounds;
      _lastBounds = bounds;
      if (previousBounds != null && !_windowsVisible) {
        unawaited(_captureSnapshot());
      }
      _channel?.invokeMethod<void>('bounds', {
        'x': bounds.left.round(),
        'y': bounds.top.round(),
        'width': bounds.width.round(),
        'height': bounds.height.round(),
        'scale': scale,
      });
    }
    if (!_windowsVisible && _snapshot == null && !_snapshotFailed) {
      if (!_capturingSnapshot) unawaited(_captureSnapshot());
      return;
    }
    if (_lastVisible != _windowsVisible) {
      _lastVisible = _windowsVisible;
      _channel?.invokeMethod<void>('visible', _windowsVisible);
      if (_windowsVisible) {
        _snapshotGeneration++;
        _snapshotFailed = false;
        final old = _snapshot;
        _snapshot = null;
        if (old != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            old.dispose();
            if (mounted) setState(() {});
          });
        }
      }
    }
  }

  @override
  void didUpdateWidget(NovelEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typingSound != widget.typingSound && _channel != null) {
      _configureSound();
    }
    if (oldWidget.focusMode != widget.focusMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusEditor());
    }
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_sessionChanged);
      oldWidget.session.controller.removeListener(_sendDocument);
      widget.session.addListener(_sessionChanged);
      widget.session.controller.addListener(_sendDocument);
      _sendDocument();
    }
    // Theme interpolation can change float colors without changing the 8-bit
    // colors sent to native editors. Avoid reformatting on those idle frames.
    if (!mapEquals(oldWidget.layout.toJson(), widget.layout.toJson()) ||
        oldWidget.textColor.toARGB32() != widget.textColor.toARGB32() ||
        oldWidget.backgroundColor.toARGB32() !=
            widget.backgroundColor.toARGB32()) {
      _channel?.invokeMethod<void>('configure', _configuration).then((_) {
        if (mounted && !_windowsVisible) unawaited(_captureSnapshot());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snapshotGeneration++;
    _snapshot?.dispose();
    _snapshot = null;
    if (_windowsReady) _channel?.invokeMethod<void>('destroy');
    widget.session.removeListener(_sessionChanged);
    widget.session.nativeLockForUpdate = null;
    widget.session.synchronizeNative = null;
    widget.session.applyNativeEdit = null;
    widget.session.previewTypingSound = null;
    widget.session.controller.removeListener(_sendDocument);
    _fallbackScroll.dispose();
    _scrollPosition.dispose();
    _fallbackFocus.dispose();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _buildEditor(context)),
      SizedBox(
        width: _gutter,
        child: IgnorePointer(
          ignoring:
              widget.overlayOpen ||
              !(ModalRoute.of(context)?.isCurrent ?? true),
          child: ScrollNavigation(
            position: _scrollPosition,
            onScrollTo: _scrollTo,
            color: widget.textColor,
          ),
        ),
      ),
    ],
  );

  Widget _buildEditor(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _macInteractive =
          !widget.overlayOpen && (ModalRoute.of(context)?.isCurrent ?? true);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncMacInteraction(),
      );
      return AppKitView(
        viewType: 'inkflow/novel-editor',
        creationParams: {..._configuration, ..._document},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _connect,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _windowsVisible =
          !widget.overlayOpen && (ModalRoute.of(context)?.isCurrent ?? true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncWindowsBounds();
      });
      return SizedBox.expand(
        key: _windowsHost,
        child: _snapshot == null
            ? null
            : IgnorePointer(
                child: RawImage(
                  image: _snapshot,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                ),
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth + _gutter;
        final bodyWidth = math.max(
          1.0,
          math.min(widget.layout.maxWidth, fullWidth - 96),
        );
        final inset = (fullWidth - bodyWidth) / 2;
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _scheduleFallbackMetrics();
            return false;
          },
          child: ScrollConfiguration(
            behavior: const _ManuscriptScrollBehavior(),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                inset,
                12,
                math.max(0, inset - _gutter),
                12,
              ),
              child: TextField(
                readOnly: widget.session.isUpdateLocked,
                controller: widget.session.controller,
                scrollController: _fallbackScroll,
                focusNode: _fallbackFocus,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                cursorHeight: widget.layout.fontSize,
                style: TextStyle(
                  color: widget.textColor,
                  fontFamily: widget.layout.fontFamily,
                  fontFamilyFallback: inkFontFallback,
                  fontSize: widget.layout.fontSize,
                  height: widget.layout.lineHeight,
                ),
                decoration: null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ManuscriptScrollBehavior extends MaterialScrollBehavior {
  const _ManuscriptScrollBehavior();
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
