import 'package:flutter/widgets.dart';

class EditorLayoutSettings {
  const EditorLayoutSettings({
    this.fontFamily = 'Songti SC',
    this.fontSize = 20,
    this.lineHeight = 1.8,
    this.paragraphGap = 8,
    this.firstLineIndentEm = 2,
    this.maxWidth = 760,
  });

  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final double paragraphGap;
  final double firstLineIndentEm;
  final double maxWidth;

  EditorLayoutSettings copyWith({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? paragraphGap,
    double? firstLineIndentEm,
    double? maxWidth,
  }) => EditorLayoutSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphGap: paragraphGap ?? this.paragraphGap,
    firstLineIndentEm: firstLineIndentEm ?? this.firstLineIndentEm,
    maxWidth: maxWidth ?? this.maxWidth,
  );

  Map<String, Object> toJson() => {
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'paragraphGap': paragraphGap,
    'firstLineIndentEm': firstLineIndentEm,
    'maxWidth': maxWidth,
  };
}

class EditorSession extends ChangeNotifier {
  EditorSession({String text = ''})
    : controller = TextEditingController(text: text) {
    controller.addListener(notifyListeners);
  }

  final TextEditingController controller;
  EditorLayoutSettings layout = const EditorLayoutSettings();

  void updateLayout(EditorLayoutSettings next) {
    layout = next;
    notifyListeners();
  }

  void applyNativeValue(Map<Object?, Object?> value) {
    final text = value['text'] as String;
    final base = (value['selectionBase'] as int).clamp(0, text.length);
    final extent = (value['selectionExtent'] as int).clamp(0, text.length);
    final start = value['composingStart'] as int? ?? -1;
    final end = value['composingEnd'] as int? ?? -1;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
      composing: start >= 0 && end >= start && end <= text.length
          ? TextRange(start: start, end: end)
          : TextRange.empty,
    );
  }

  @override
  void dispose() {
    controller.removeListener(notifyListeners);
    controller.dispose();
    super.dispose();
  }
}
