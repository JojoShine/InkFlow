import '../works/work_models.dart';
import '../appearance/appearance_settings.dart';
import '../editor/editor_session.dart';
import '../../core/typography.dart';
import '../typing_sound/typing_sound_settings.dart';

enum LibraryView { list, cards }

class RecentWork {
  const RecentWork({
    required this.path,
    required this.workId,
    required this.title,
    this.bookmark = '',
    this.coverFile,
    this.details = const WorkDetails(),
    this.chapterId,
    this.selectionOffset = 0,
    this.scrollOffset = 0,
  });
  final String path;
  final String workId;
  final String title;
  final String bookmark;
  final String? coverFile;
  final WorkDetails details;
  final String? chapterId;
  final int selectionOffset;
  final double scrollOffset;
  RecentWork position(String? chapter, int selection, double scroll) =>
      RecentWork(
        path: path,
        workId: workId,
        title: title,
        bookmark: bookmark,
        coverFile: coverFile,
        details: details,
        chapterId: chapter,
        selectionOffset: selection,
        scrollOffset: scroll,
      );
  RecentWork withCover(String? cover) => RecentWork(
    path: path,
    workId: workId,
    title: title,
    bookmark: bookmark,
    chapterId: chapterId,
    selectionOffset: selectionOffset,
    scrollOffset: scrollOffset,
    coverFile: cover,
    details: details,
  );
  RecentWork withDetails(WorkDetails value) => RecentWork(
    path: path,
    workId: workId,
    title: title,
    bookmark: bookmark,
    chapterId: chapterId,
    selectionOffset: selectionOffset,
    scrollOffset: scrollOffset,
    coverFile: coverFile,
    details: value,
  );
  RecentWork withManifest(WorkManifest manifest) => RecentWork(
    path: path,
    workId: workId,
    title: manifest.title,
    bookmark: bookmark,
    chapterId: chapterId,
    selectionOffset: selectionOffset,
    scrollOffset: scrollOffset,
    coverFile: manifest.coverFile,
    details: manifest.details,
  );
  Map<String, Object?> toJson() => {
    if (coverFile != null) 'coverFile': coverFile,
    'details': details.toJson(),
    'path': path,
    'workId': workId,
    'title': title,
    'bookmark': bookmark,
    'chapterId': chapterId,
    'selectionOffset': selectionOffset,
    'scrollOffset': scrollOffset,
  };
  static RecentWork fromJson(Map<String, dynamic> json) => RecentWork(
    details: WorkDetails.fromJson(json['details']),
    coverFile: validCoverFile(json['coverFile'])
        ? json['coverFile'] as String
        : null,
    path: json['path'] as String,
    workId: json['workId'] as String,
    title: json['title'] as String,
    bookmark: json['bookmark'] as String? ?? '',
    chapterId: json['chapterId'] as String?,
    selectionOffset: json['selectionOffset'] as int? ?? 0,
    scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0,
  );
}

class DevicePreferences {
  const DevicePreferences({
    this.appearance = const AppearanceSettings(),
    this.layout = const EditorLayoutSettings(),
    this.recentWorks = const [],
    this.libraryView = LibraryView.list,
    this.trashedWorks = const [],
    this.libraryRootPath,
    this.libraryRootBookmark = '',
    this.typingSound = const TypingSoundSettings(),
  });
  final AppearanceSettings appearance;
  final EditorLayoutSettings layout;
  final List<RecentWork> recentWorks;
  final LibraryView libraryView;
  final List<RecentWork> trashedWorks;
  final String? libraryRootPath;
  final String libraryRootBookmark;
  final TypingSoundSettings typingSound;
  DevicePreferences copyWith({
    AppearanceSettings? appearance,
    EditorLayoutSettings? layout,
    List<RecentWork>? recentWorks,
    LibraryView? libraryView,
    List<RecentWork>? trashedWorks,
    String? libraryRootPath,
    String? libraryRootBookmark,
    TypingSoundSettings? typingSound,
  }) => DevicePreferences(
    appearance: appearance ?? this.appearance,
    layout: layout ?? this.layout,
    recentWorks: recentWorks ?? this.recentWorks,
    libraryView: libraryView ?? this.libraryView,
    trashedWorks: trashedWorks ?? this.trashedWorks,
    libraryRootPath: libraryRootPath ?? this.libraryRootPath,
    libraryRootBookmark: libraryRootBookmark ?? this.libraryRootBookmark,
    typingSound: typingSound ?? this.typingSound,
  );
  Map<String, Object?> toJson() => {
    'version': 1,
    'libraryView': libraryView.name,
    'appearance': appearance.toJson(),
    'layout': layout.toJson(),
    'recentWorks': recentWorks.map((work) => work.toJson()).toList(),
    'trashedWorks': trashedWorks.map((work) => work.toJson()).toList(),
    'libraryRootPath': libraryRootPath,
    'libraryRootBookmark': libraryRootBookmark,
    'typingSound': typingSound.toJson(),
  };
  static DevicePreferences fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('设备设置版本不兼容');
    final layout = json['layout'] as Map<String, dynamic>;
    return DevicePreferences(
      libraryView: json['libraryView'] == 'cards'
          ? LibraryView.cards
          : LibraryView.list,
      libraryRootPath: json['libraryRootPath'] as String?,
      libraryRootBookmark: json['libraryRootBookmark'] as String? ?? '',
      typingSound: TypingSoundSettings.fromJson(
        json['typingSound'] as Map<String, dynamic>? ?? {},
      ),
      appearance: AppearanceSettings.fromJson(
        json['appearance'] as Map<String, dynamic>,
      ),
      layout: EditorLayoutSettings(
        fontFamily: layout['fontFamily'] as String? ?? inkFontFamily,
        fontSize: ((layout['fontSize'] as num?)?.toDouble() ?? 20).clamp(
          12,
          36,
        ),
        lineHeight: ((layout['lineHeight'] as num?)?.toDouble() ?? 1.8).clamp(
          1.2,
          2.6,
        ),
        paragraphGap: ((layout['paragraphGap'] as num?)?.toDouble() ?? 8).clamp(
          0,
          32,
        ),
        firstLineIndentEm:
            ((layout['firstLineIndentEm'] as num?)?.toDouble() ?? 2).clamp(
              0,
              4,
            ),
        maxWidth: ((layout['maxWidth'] as num?)?.toDouble() ?? 760).clamp(
          480,
          1000,
        ),
      ),
      recentWorks: List.unmodifiable(
        (json['recentWorks'] as List).map(
          (value) => RecentWork.fromJson(value as Map<String, dynamic>),
        ),
      ),
      trashedWorks: List.unmodifiable(
        (json['trashedWorks'] as List? ?? []).map(
          (value) => RecentWork.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }
}
