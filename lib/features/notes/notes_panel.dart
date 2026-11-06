import '../../app/labeled_field.dart';
import 'package:flutter/material.dart';
import '../../app/ui_actions.dart';
import '../appearance/theme_presets.dart';
import '../recovery/recovery_panel.dart';
import '../workbench/workbench_controller.dart';
import 'note_models.dart';
import '../../app/ink_icons.dart';

const _noteLabels = {
  NoteKind.outline: '大纲',
  NoteKind.character: '角色',
  NoteKind.inspiration: '灵感',
};

class NotesPanel extends StatefulWidget {
  const NotesPanel({
    super.key,
    required this.controller,
    required this.kind,
    this.width = 320,
  });
  final WorkbenchController controller;
  final double width;
  final NoteKind kind;
  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  String? selectedId;
  @override
  void didUpdateWidget(NotesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.controller.work != widget.controller.work) {
      selectedId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final colors = InkPalette.of(context);
    final selected = selectedId == null ? null : c.notes!.find(selectedId!);
    const labels = _noteLabels;
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.paper.withValues(alpha: 0.96),
        border: Border(left: BorderSide(color: colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 0),
            child: Row(
              children: [
                for (final kind in NoteKind.values)
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() => selectedId = null);
                        c.setPanel(kind);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: widget.kind == kind
                                  ? colors.accent
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          labels[kind]!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: widget.kind == kind
                                ? colors.accent
                                : colors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!c.work!.notesComplete && c.work!.isLazy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已检查 ${c.work!.notesChecked} / ${c.work!.notesTotal ?? '…'} 份资料',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: c.loadMoreNotes,
                    child: const Text('继续加载资料'),
                  ),
                ],
              ),
            ),
          if (selected != null && !selected.isDeleted)
            Expanded(
              child: _NoteForm(
                key: ValueKey(selected.id),
                note: selected,
                controller: c,
                onBack: () => setState(() => selectedId = null),
                onOpen: (id) => setState(() => selectedId = id),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${labels[widget.kind]}列表',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(InkIcons.add),
                    label: Text('新建${labels[widget.kind]}'),
                    onPressed: () async {
                      final note = await c.notes!.create(widget.kind);
                      if (note != null && mounted) {
                        setState(() => selectedId = note.id);
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: _noteList(context, c)),
          ],
        ],
      ),
    );
  }

  Widget _noteList(BuildContext context, WorkbenchController c) {
    final colors = InkPalette.of(context);
    final notes = c.notes!.ofKind(widget.kind);
    if (notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Text(
          c.work!.isLazy && !c.work!.notesComplete
              ? '当前批次没有${_noteLabels[widget.kind]}，可继续加载资料。'
              : '还没有${_noteLabels[widget.kind]}。\n点击“新建${_noteLabels[widget.kind]}”开始记录。',
          style: TextStyle(color: colors.muted, fontSize: 14, height: 1.9),
        ),
      );
    }
    final flattened = <(NoteRecord, int)>[];
    if (widget.kind == NoteKind.outline) {
      final visited = <String>{};
      void collect(String? parent, int depth) {
        for (final note in notes.where((note) => note.parentId == parent)) {
          if (!visited.add(note.id)) continue;
          flattened.add((note, depth));
          collect(note.id, depth + 1);
        }
      }

      collect(null, 0);
      for (final note in notes.where((note) => !visited.contains(note.id))) {
        flattened.add((note, 0));
      }
    } else {
      flattened.addAll(notes.map((note) => (note, 0)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      itemCount: flattened.length,
      itemBuilder: (context, index) {
        final (note, depth) = flattened[index];
        return InkWell(
          borderRadius: BorderRadius.circular(4),
          hoverColor: colors.selection.withValues(alpha: .35),
          focusColor: colors.selection.withValues(alpha: .35),
          onTap: () => setState(() => selectedId = note.id),
          child: Padding(
            padding: EdgeInsets.fromLTRB(8 + depth.clamp(0, 4) * 12, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.kind == NoteKind.outline)
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.background,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  )
                else
                  Icon(
                    widget.kind == NoteKind.character
                        ? InkIcons.person
                        : InkIcons.idea,
                    size: 20,
                    color: colors.muted,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                      for (final content in [
                        note.summary,
                        note.body,
                      ].where((content) => content.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            content,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.muted,
                              height: 1.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteForm extends StatefulWidget {
  const _NoteForm({
    super.key,
    required this.note,
    required this.controller,
    required this.onBack,
    required this.onOpen,
  });
  final NoteRecord note;
  final WorkbenchController controller;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;
  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  late final title = TextEditingController(text: widget.note.title);
  late final summary = TextEditingController(text: widget.note.summary);
  late final body = TextEditingController(text: widget.note.body);

  @override
  void didUpdateWidget(_NoteForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final pair in [
      (title, widget.note.title),
      (summary, widget.note.summary),
      (body, widget.note.body),
    ]) {
      if (pair.$1.text != pair.$2) {
        pair.$1.value = TextEditingValue(
          text: pair.$2,
          selection: TextSelection.collapsed(
            offset: pair.$1.selection.extentOffset.clamp(0, pair.$2.length),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    title.dispose();
    summary.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final note = c.notes!.find(widget.note.id)!;
    final colors = InkPalette.of(context);
    final label = _noteLabels[note.kind]!;
    final outlines = c.notes!.ofKind(NoteKind.outline);
    bool canBeParent(NoteRecord candidate) {
      String? id = candidate.id;
      final visited = <String>{};
      while (id != null && visited.add(id)) {
        if (id == note.id) return false;
        id = c.notes!.find(id)?.parentId;
      }
      return true;
    }

    final parentOptions = outlines.where(canBeParent).toList();
    final status = c.notes!.failure != null
        ? '保存失败：${c.notes!.failure}'
        : c.notes!.isDirty
        ? '正在保存…'
        : '修改会自动保存';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(InkIcons.back, size: 18),
                label: Text('返回$label列表'),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (action) async {
                  if (action == 'history') {
                    await showHistory(context, c, note.id);
                  } else {
                    await uiAction(context, () async {
                      await c.trashRecord(note.id);
                      if (mounted) widget.onBack();
                    });
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'history', child: Text('查看历史版本')),
                  PopupMenuItem(value: 'trash', child: Text('移入回收站')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '更多',
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                      const SizedBox(width: 8),
                      Icon(InkIcons.more, size: 16, color: colors.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: c.notes!.failure == null
                  ? colors.muted
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
        Divider(height: 1, color: colors.line),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              _field(
                label: note.kind == NoteKind.character ? '角色名称' : '$label标题',
                controller: title,
                fieldKey: 'note-title',
                hint: note.kind == NoteKind.character ? '例如：林晚' : '输入$label标题',
                onChanged: (value) =>
                    c.notes!.update(note.copyWith(title: value)),
              ),
              if (note.kind == NoteKind.character)
                _field(
                  label: '角色简介',
                  controller: summary,
                  fieldKey: 'note-summary',
                  hint: '这个人是谁？在故事中是什么身份？',
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (value) =>
                      c.notes!.update(note.copyWith(summary: value)),
                ),
              _field(
                label: switch (note.kind) {
                  NoteKind.character => '详细设定',
                  NoteKind.outline => '情节内容',
                  NoteKind.inspiration => '灵感内容',
                },
                controller: body,
                fieldKey: 'note-body',
                hint: switch (note.kind) {
                  NoteKind.character => '记录性格、外貌、经历和人物关系…',
                  NoteKind.outline => '这一段发生什么？有哪些关键转折？',
                  NoteKind.inspiration => '记下一句话、一个画面，或一个情节点…',
                },
                minLines: 6,
                maxLines: 12,
                onChanged: (value) =>
                    c.notes!.update(note.copyWith(body: value)),
              ),
              if (note.kind == NoteKind.inspiration) ...[
                Text('关联章节', style: TextStyle(fontSize: 14, color: colors.ink)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  icon: const Icon(InkIcons.chevronDown, size: 12),
                  key: ValueKey('chapter-${note.chapterId}'),
                  initialValue: note.chapterId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('不关联章节')),
                    for (final chapter in c.work!.chapters.values.where(
                      (chapter) =>
                          !chapter.isDeleted || chapter.id == note.chapterId,
                    ))
                      DropdownMenuItem(
                        value: chapter.id,
                        child: Text(
                          '${chapter.title}${chapter.isDeleted ? '（回收站）' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      c.notes!.linkInspiration(note.id, value),
                ),
                const SizedBox(height: 8),
                Text(
                  '可将这条灵感关联到某一章，也可以单独保留。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.muted,
                    height: 1.6,
                  ),
                ),
              ],
              if (note.kind == NoteKind.outline) ...[
                Text(
                  '上一级大纲',
                  style: TextStyle(fontSize: 14, color: colors.ink),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  icon: const Icon(InkIcons.chevronDown, size: 12),
                  key: ValueKey('parent-${note.parentId}'),
                  initialValue: parentOptions.any((n) => n.id == note.parentId)
                      ? note.parentId
                      : null,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('无（一级大纲）')),
                    for (final parent in parentOptions)
                      DropdownMenuItem(
                        value: parent.id,
                        child: Text(
                          parent.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => uiAction(
                    context,
                    () => c.notes!.moveOutline(note.id, value, note.order),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '选择后，这条大纲会显示在所选大纲下面。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.muted,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () async {
                    final created = await c.notes!.create(
                      NoteKind.outline,
                      parentId: note.id,
                    );
                    if (created != null && mounted) widget.onOpen(created.id);
                  },
                  icon: const Icon(InkIcons.add, size: 18),
                  label: const Text('新建子大纲'),
                ),
                const SizedBox(height: 8),
                Text(
                  '在“${note.title}”下面补充下一层情节。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.muted,
                    height: 1.6,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String fieldKey,
    required String hint,
    required ValueChanged<String> onChanged,
    int minLines = 1,
    int maxLines = 1,
  }) {
    final colors = InkPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LabeledField(
        label: label,
        child: TextField(
          key: ValueKey(fieldKey),
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, height: 1.6, color: colors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: colors.muted,
              height: 1.6,
            ),
            filled: true,
            fillColor: colors.background.withValues(alpha: .45),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
