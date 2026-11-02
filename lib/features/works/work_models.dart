import 'dart:math';

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

bool validId(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(value);

class WorkManifest {
  const WorkManifest({
    required this.workId,
    required this.title,
    required this.chapterIds,
  });
  final String workId;
  final String title;
  final List<String> chapterIds;

  WorkManifest copyWith({String? title, List<String>? chapterIds}) =>
      WorkManifest(
        workId: workId,
        title: title ?? this.title,
        chapterIds: List.unmodifiable(chapterIds ?? this.chapterIds),
      );

  Map<String, Object> toJson() => {
    'formatVersion': 1,
    'workId': workId,
    'title': title,
    'chapterIds': chapterIds,
  };
}

class ChapterRecord {
  const ChapterRecord({required this.id, required this.title, this.deletedAt});
  final String id;
  final String title;
  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;

  ChapterRecord rename(String title) =>
      ChapterRecord(id: id, title: title, deletedAt: deletedAt);
  ChapterRecord trash(DateTime when) =>
      ChapterRecord(id: id, title: title, deletedAt: when);
  ChapterRecord restore() => ChapterRecord(id: id, title: title);
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'deletedAt': deletedAt?.toIso8601String(),
  };
}
