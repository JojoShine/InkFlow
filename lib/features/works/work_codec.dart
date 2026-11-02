import 'dart:convert';
import 'work_models.dart';

class WorkCodec {
  static Map<String, dynamic> object(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('作品记录应为 JSON 对象');
    }
    return value;
  }

  static WorkManifest decodeManifest(List<int> bytes) {
    final json = object(bytes);
    if (json['formatVersion'] != 1 ||
        !validId(json['workId']) ||
        json['title'] is! String ||
        json['chapterIds'] is! List) {
      throw const FormatException('作品格式不兼容或清单损坏，原文件已保留');
    }
    final ids = json['chapterIds'] as List;
    if (ids.any((id) => !validId(id)) || ids.toSet().length != ids.length) {
      throw const FormatException('章节标识不合法或重复，原文件已保留');
    }
    return WorkManifest(
      workId: json['workId'],
      title: json['title'],
      chapterIds: List<String>.unmodifiable(ids),
    );
  }

  static List<int> encodeManifest(WorkManifest work) => encode(work.toJson());
  static List<int> encode(Map<String, Object?> value) =>
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(value)}\n');

  static ChapterRecord decodeChapter(List<int> bytes) {
    final json = object(bytes);
    if (!validId(json['id']) || json['title'] is! String) {
      throw const FormatException('章节信息损坏');
    }
    return ChapterRecord(
      id: json['id'],
      title: json['title'],
      deletedAt: date(json['deletedAt']),
    );
  }

  static DateTime? date(Object? value) {
    if (value == null) return null;
    final date = value is String ? DateTime.tryParse(value) : null;
    if (date == null) throw const FormatException('记录时间不合法');
    return date;
  }
}
