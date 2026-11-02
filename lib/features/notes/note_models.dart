import '../works/work_codec.dart';
import '../works/work_models.dart';

enum NoteKind { outline, character, inspiration }

const _absent = Object();

class NoteRecord {
  const NoteRecord({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.summary = '',
    this.parentId,
    this.order = 0,
    this.chapterId,
    this.deletedAt,
  });

  final String id;
  final NoteKind kind;
  final String title;
  final String body;
  final String summary;
  final String? parentId;
  final int order;
  final String? chapterId;
  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;

  NoteRecord copyWith({
    String? title,
    String? body,
    String? summary,
    Object? parentId = _absent,
    int? order,
    Object? chapterId = _absent,
    Object? deletedAt = _absent,
  }) => NoteRecord(
    id: id,
    kind: kind,
    title: title ?? this.title,
    body: body ?? this.body,
    summary: summary ?? this.summary,
    order: order ?? this.order,
    parentId: identical(parentId, _absent)
        ? this.parentId
        : parentId as String?,
    chapterId: identical(chapterId, _absent)
        ? this.chapterId
        : chapterId as String?,
    deletedAt: identical(deletedAt, _absent)
        ? this.deletedAt
        : deletedAt as DateTime?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'body': body,
    'summary': summary,
    'parentId': parentId,
    'order': order,
    'chapterId': chapterId,
    'deletedAt': deletedAt?.toIso8601String(),
  };

  static NoteRecord decode(List<int> bytes) {
    final json = WorkCodec.object(bytes);
    if (!validId(json['id']) ||
        json['title'] is! String ||
        json['body'] is! String ||
        json['summary'] is! String ||
        json['order'] is! int ||
        (json['parentId'] != null && !validId(json['parentId'])) ||
        (json['chapterId'] != null && !validId(json['chapterId']))) {
      throw const FormatException('创作资料格式损坏');
    }
    final kinds = NoteKind.values.where((kind) => kind.name == json['kind']);
    if (kinds.isEmpty) throw const FormatException('未知的创作资料类型');
    return NoteRecord(
      id: json['id'],
      kind: kinds.single,
      title: json['title'],
      body: json['body'],
      summary: json['summary'],
      parentId: json['parentId'],
      chapterId: json['chapterId'],
      order: json['order'],
      deletedAt: WorkCodec.date(json['deletedAt']),
    );
  }
}
