import 'dart:convert';
import '../../core/platform/gb18030_decoder.dart';
import '../works/work_repository.dart';

class TextTransfer {
  static String decode(List<int> bytes, {String encoding = 'utf-8'}) {
    var text = switch (encoding.toLowerCase()) {
      'utf-8' => utf8.decode(bytes),
      'gb18030' => decodeGb18030(bytes),
      _ => throw const FormatException('不支持的文本编码'),
    };
    if (text.startsWith('\ufeff')) text = text.substring(1);
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static Future<List<int>> exportChapter(WorkHandle work, String id) async =>
      utf8.encode((await work.readChapter(id)).text);
  static Future<List<int>> exportWork(WorkHandle work) async {
    final chapters = <String>[];
    for (final id in work.manifest.chapterIds) {
      if (work.chapters[id]!.isDeleted) continue;
      final document = await work.readChapter(id);
      chapters.add('${document.record.title}\n\n${document.text}');
    }
    return utf8.encode(chapters.isEmpty ? '' : '${chapters.join('\n\n')}\n');
  }
}
