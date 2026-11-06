import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/ui_actions.dart';
import '../../core/storage/record_store.dart';
import '../../core/storage/operation_journal.dart';
import '../appearance/theme_presets.dart';
import '../notes/note_models.dart';
import '../works/work_codec.dart';
import '../workbench/workbench_controller.dart';

String _date(DateTime date) {
  final d = date.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${pad(d.month)}-${pad(d.day)} ${pad(d.hour)}:${pad(d.minute)}';
}

Future<void> showHistory(
  BuildContext context,
  WorkbenchController c,
  String recordId,
) => uiAction(context, () async {
  final entries = await c.history.list(c.workKey, recordId);
  if (!context.mounted) return;
  if (entries.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('还没有历史版本')));
    return;
  }
  var selected = entries.last;
  var content = await c.history.read(selected);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('历史版本'),
        content: SizedBox(
          width: 820,
          height: 480,
          child: Row(
            children: [
              SizedBox(
                width: 190,
                child: ListView(
                  children: [
                    for (final entry in entries.reversed)
                      ListTile(
                        dense: true,
                        selected: entry.path == selected.path,
                        title: Text(
                          _date(entry.createdAt),
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () => uiAction(context, () async {
                          final bytes = await c.history.read(entry);
                          setState(() {
                            selected = entry;
                            content = bytes;
                          });
                        }),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 24),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _preview(content, c.work!.notes.containsKey(recordId)),
                    style: const TextStyle(fontSize: 15, height: 1.8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await uiAction(
                context,
                () => c.restoreHistory(selected, recordId),
              );
            },
            child: const Text('恢复此版本'),
          ),
        ],
      ),
    ),
  );
});

String _preview(List<int> bytes, bool note) {
  if (note) {
    try {
      final record = NoteRecord.decode(bytes);
      return [
        record.title,
        if (record.summary.isNotEmpty) record.summary,
        record.body,
      ].join('\n\n');
    } on FormatException {
      return '这个版本暂时无法预览，原文件已保留。';
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

Future<void> showTrash(BuildContext context, WorkbenchController c) async {
  await c.work!.ensureAllMetadata();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final deleted = <(String, String)>[
          for (final chapter in c.work!.chapters.values.where(
            (record) => record.isDeleted,
          ))
            (chapter.id, chapter.title),
          for (final note in c.work!.notes.values.where(
            (record) => record.isDeleted,
          ))
            (note.id, note.title),
        ];
        return AlertDialog(
          title: const Text('作品回收站'),
          content: SizedBox(
            width: 620,
            height: 400,
            child: deleted.isEmpty
                ? const Center(child: Text('回收站是空的'))
                : ListView(
                    children: [
                      for (final entry in deleted)
                        ListTile(
                          title: Text(entry.$2),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => uiAction(context, () async {
                                  await c.restoreRecord(entry.$1);
                                  setState(() {});
                                }),
                                child: const Text('恢复'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final confirmed = await confirmAction(
                                    context,
                                    '永久删除“${entry.$2}”？',
                                    '此条目及其子条目将从作品中移除。请确认已不再需要这些内容。',
                                    action: '永久删除',
                                  );
                                  if (confirmed && context.mounted) {
                                    await uiAction(context, () async {
                                      await c.purgeRecord(entry.$1);
                                      setState(() {});
                                    });
                                  }
                                },
                                child: const Text('永久删除'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showConflicts(BuildContext context, WorkbenchController c) =>
    uiAction(context, () async {
      await c.scanSyncCopies();
      final root = Directory('${c.work!.root.path}/.inkflow/conflicts');
      if (!await root.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('没有待处理的冲突')));
        }
        return;
      }
      final entries = await root
          .list()
          .where((entry) => entry is Directory)
          .cast<Directory>()
          .toList();
      for (final directory in entries) {
        final infoFile = File('${directory.path}/info.json');
        if (!await infoFile.exists() || !context.mounted) continue;
        final info =
            jsonDecode(await infoFile.readAsString()) as Map<String, dynamic>;
        final path = info['path'] as String;
        final current = await c.work!.store.read(path);
        final source = info['externalSource'] as String?;
        final external = source == null
            ? current?.bytes
            : (await c.work!.store.read(source))?.bytes ??
                  await File('${directory.path}/external.bin').readAsBytes();
        final activePath = 'chapters/${c.activeChapterId}.txt';
        final local = path == activePath
            ? utf8.encode(c.session.controller.text)
            : info['localMissing'] == true
            ? null
            : await File('${directory.path}/local.bin').readAsBytes();
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('比较冲突版本'),
            content: SizedBox(
              width: 900,
              height: 490,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '双方副本都会保留。请选择当前作品采用的内容。',
                    style: TextStyle(
                      color: InkPalette.of(context).muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ConflictText(
                            title: '本机版本',
                            bytes: local,
                            isNote: path.startsWith('notes/'),
                          ),
                        ),
                        const VerticalDivider(width: 24),
                        Expanded(
                          child: _ConflictText(
                            title: '外部当前版本',
                            bytes: external,
                            isNote: path.startsWith('notes/'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('暂不处理'),
              ),
              TextButton(
                onPressed: external == null
                    ? null
                    : () async {
                        Navigator.pop(dialogContext);
                        await _resolve(
                          context,
                          c,
                          directory,
                          path,
                          external,
                          current?.version,
                        );
                      },
                child: const Text('采用外部版本'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _resolve(
                    context,
                    c,
                    directory,
                    path,
                    local,
                    current?.version,
                  );
                },
                child: const Text('采用本机版本'),
              ),
            ],
          ),
        );
      }
    });

Future<void> _resolve(
  BuildContext context,
  WorkbenchController c,
  Directory directory,
  String path,
  List<int>? bytes,
  RecordVersion? expected,
) => uiAction(context, () async {
  if (bytes != null) {
    if (path == 'work.json') {
      final manifest = WorkCodec.decodeManifest(bytes);
      if (manifest.workId != c.work!.manifest.workId) {
        throw const FormatException('这个清单属于其他作品');
      }
      for (final id in manifest.chapterIds) {
        final metadata = await c.work!.store.read('chapters/$id.json');
        if (metadata == null ||
            await c.work!.store.read('chapters/$id.txt') == null) {
          throw const FormatException('外部章节文件尚未同步完整，请稍后处理清单');
        }
        WorkCodec.decodeChapter(metadata.bytes);
      }
    } else if (path.startsWith('notes/')) {
      final note = NoteRecord.decode(bytes);
      if (!path.endsWith('/${note.id}.json')) {
        throw const FormatException('资料与文件标识不一致');
      }
    } else if (path.endsWith('.json')) {
      final chapter = WorkCodec.decodeChapter(bytes);
      if (!path.endsWith('/${chapter.id}.json')) {
        throw const FormatException('章节与文件标识不一致');
      }
    } else if (path.endsWith('.txt')) {
      utf8.decode(bytes);
    }
  }
  final current = await c.work!.store.read(path);
  final parts = path.split('/');
  final recordId = parts.length > 1 ? parts.last.split('.').first : null;
  if (current != null && recordId != null) {
    await c.history.capture(c.workKey, recordId, current.bytes, DateTime.now());
  }
  final result = bytes == null
      ? await c.work!.store.delete(path, expected: expected)
      : await c.work!.store.write(path, bytes, expected: expected);
  if (!result.isSaved) throw SaveException(result);
  final resolved = Directory(
    '${c.work!.root.path}/.inkflow/resolved-conflicts',
  );
  await resolved.create(recursive: true);
  await directory.rename(
    '${resolved.path}/${directory.uri.pathSegments.where((part) => part.isNotEmpty).last}',
  );
  await c.reloadAfterConflict(path);
});

class _ConflictText extends StatelessWidget {
  const _ConflictText({
    required this.title,
    required this.bytes,
    required this.isNote,
  });
  final String title;
  final List<int>? bytes;
  final bool isNote;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 16),
      Expanded(
        child: SingleChildScrollView(
          child: SelectableText(
            bytes == null ? '此版本中已删除' : _preview(bytes!, isNote),
            style: const TextStyle(fontSize: 14, height: 1.8),
          ),
        ),
      ),
    ],
  );
}
