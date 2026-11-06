enum WorkLoadStage { directory, recovery, chapter, notes, refresh }

class WorkLoadProgress {
  const WorkLoadProgress(
    this.stage, {
    this.targetId,
    this.completed,
    this.total,
    this.slow = false,
    this.error,
  });
  final WorkLoadStage stage;
  final String? targetId;
  final int? completed, total;
  final bool slow;
  final String? error;
  String get label => switch (stage) {
    WorkLoadStage.directory => '正在读取作品目录',
    WorkLoadStage.recovery => '正在恢复未完成操作',
    WorkLoadStage.chapter => '正在加载章节',
    WorkLoadStage.notes => '正在读取资料',
    WorkLoadStage.refresh => '正在检查外部更新',
  };
}
