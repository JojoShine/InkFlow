import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_session.dart';

class NovelEditor extends StatefulWidget {
  const NovelEditor({
    super.key,
    required this.session,
    required this.layout,
    required this.textColor,
    required this.backgroundColor,
  });

  final EditorSession session;
  final EditorLayoutSettings layout;
  final Color textColor;
  final Color backgroundColor;

  @override
  State<NovelEditor> createState() => _NovelEditorState();
}

class _NovelEditorState extends State<NovelEditor> {
  MethodChannel? _channel;
  bool _receiving = false;

  Map<String, Object> get _configuration => {
    ...widget.layout.toJson(),
    'textColor': widget.textColor.toARGB32(),
    'backgroundColor': widget.backgroundColor.toARGB32(),
  };

  Map<String, Object> get _document => {
    'text': widget.session.controller.text,
    'selectionBase': widget.session.controller.selection.baseOffset,
    'selectionExtent': widget.session.controller.selection.extentOffset,
  };

  @override
  void initState() {
    super.initState();
    widget.session.controller.addListener(_sendDocument);
  }

  Future<void> _connect(int id) async {
    _channel = MethodChannel('inkflow/editor/$id');
    _channel!.setMethodCallHandler((call) async {
      if (call.method == 'changed' && mounted) {
        _receiving = true;
        try {
          widget.session.applyNativeValue(call.arguments as Map);
        } finally {
          _receiving = false;
        }
      }
    });
    await _channel!.invokeMethod('configure', _configuration);
    await _channel!.invokeMethod('load', _document);
  }

  void _sendDocument() {
    if (!_receiving) _channel?.invokeMethod<void>('load', _document);
  }

  @override
  void didUpdateWidget(NovelEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.controller.removeListener(_sendDocument);
      widget.session.controller.addListener(_sendDocument);
      _sendDocument();
    }
    if (oldWidget.layout != widget.layout ||
        oldWidget.textColor != widget.textColor ||
        oldWidget.backgroundColor != widget.backgroundColor) {
      _channel?.invokeMethod<void>('configure', _configuration);
    }
  }

  @override
  void dispose() {
    widget.session.controller.removeListener(_sendDocument);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return AppKitView(
        viewType: 'inkflow/novel-editor',
        creationParams: {..._configuration, ..._document},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _connect,
      );
    }
    return TextField(
      controller: widget.session.controller,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(
        color: widget.textColor,
        fontFamily: widget.layout.fontFamily,
        fontSize: widget.layout.fontSize,
        height: widget.layout.lineHeight,
      ),
      decoration: const InputDecoration(border: InputBorder.none),
    );
  }
}
