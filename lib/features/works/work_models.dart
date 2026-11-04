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

bool validCoverFile(Object? value) =>
    value is String &&
    RegExp(r'^assets/covers/[a-f0-9]{64}\.png$').hasMatch(value);

class WorkVolume {
  const WorkVolume({required this.id, required this.title});
  final String id;
  final String title;
  WorkVolume rename(String title) => WorkVolume(id: id, title: title);
  Map<String, Object> toJson() => {'id': id, 'title': title};
}

const workAudiences = ['不限', '男频', '女频'];
const workTagOptions = [
  '玄幻',
  '奇幻',
  '都市',
  '言情',
  '悬疑',
  '科幻',
  '历史',
  '武侠',
  '仙侠',
  '游戏',
  '现实',
  '其他',
];

class WorkDetails {
  const WorkDetails({
    this.audience = '不限',
    this.tags = const [],
    this.synopsis = '',
  });
  final String audience;
  final List<String> tags;
  final String synopsis;

  Map<String, Object> toJson() => {
    'audience': audience,
    'tags': tags,
    'synopsis': synopsis,
  };

  static WorkDetails fromJson(Object? value) {
    if (value == null) return const WorkDetails();
    if (value is! Map<String, dynamic>) throw const FormatException('作品信息损坏');
    final audience = value['audience'] ?? '不限';
    final tags = value['tags'] ?? <String>[];
    final synopsis = value['synopsis'] ?? '';
    if (audience is! String ||
        tags is! List ||
        tags.any((tag) => tag is! String) ||
        synopsis is! String) {
      throw const FormatException('作品信息损坏');
    }
    return WorkDetails(
      audience: audience,
      tags: List<String>.unmodifiable(tags),
      synopsis: synopsis,
    );
  }
}

class WorkManifest {
  const WorkManifest({
    required this.workId,
    required this.title,
    required this.chapterIds,
    List<WorkVolume>? volumes,
    this.chapterVolumes = const {},
    this.coverFile,
    this.details = const WorkDetails(),
  }) : _volumes = volumes;
  final String workId;
  final String title;
  final List<String> chapterIds;
  final Map<String, String> chapterVolumes;
  final String? coverFile;
  final WorkDetails details;
  final List<WorkVolume>? _volumes;
  List<WorkVolume> get volumes =>
      _volumes ?? [WorkVolume(id: workId, title: '第一卷')];

  WorkManifest copyWith({
    String? title,
    List<String>? chapterIds,
    List<WorkVolume>? volumes,
    Map<String, String>? chapterVolumes,
    String? coverFile,
    bool clearCover = false,
    WorkDetails? details,
  }) => WorkManifest(
    workId: workId,
    details: details ?? this.details,
    coverFile: clearCover ? null : coverFile ?? this.coverFile,
    title: title ?? this.title,
    chapterIds: List.unmodifiable(chapterIds ?? this.chapterIds),
    volumes: List.unmodifiable(volumes ?? this.volumes),
    chapterVolumes: Map.unmodifiable(chapterVolumes ?? this.chapterVolumes),
  );

  Map<String, Object> toJson() => {
    'formatVersion': 1,
    if (details.audience != '不限' ||
        details.tags.isNotEmpty ||
        details.synopsis.isNotEmpty)
      'details': details.toJson(),
    'coverFile': ?coverFile,
    'workId': workId,
    'title': title,
    'chapterIds': chapterIds,
    'volumes': volumes.map((volume) => volume.toJson()).toList(),
    'chapterVolumes': chapterVolumes,
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
