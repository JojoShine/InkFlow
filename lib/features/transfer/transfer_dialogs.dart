import '../../app/labeled_field.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../app/ink_icons.dart';
import 'package:path/path.dart' as p;
import '../../app/ui_actions.dart';
import '../../core/platform/selected_file_output.dart';
import '../workbench/workbench_controller.dart';
import 'text_transfer.dart';
import 'backup_service.dart';

const _textType = XTypeGroup(
  label: '纯文本',
  extensions: ['txt'],
  uniformTypeIdentifiers: ['public.plain-text'],
);
const _zipType = XTypeGroup(
  label: '作品备份',
  extensions: ['zip'],
  uniformTypeIdentifiers: ['public.zip-archive'],
);

String _filename(String title) =>
    title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');

Future<void> importText(BuildContext context, WorkbenchController c) =>
    uiAction(context, () async {
      if (!await c.flushAll()) return;
      final file = await openFile(acceptedTypeGroups: [_textType]);
      if (file == null || !context.mounted) return;
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      var title = p.basenameWithoutExtension(file.path);
      var encoding = 'utf-8';
      String decoded = '', error = '';
      void decode() {
        try {
          decoded = TextTransfer.decode(bytes, encoding: encoding);
          error = '';
        } on FormatException catch (failure) {
          decoded = '';
          error = failure.message;
        }
      }

      decode();
      final result = await showDialog<(String, String)>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('导入章节'),
            content: SizedBox(
              width: 680,
              height: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledField(
                    label: '章节名称',
                    child: TextFormField(
                      initialValue: title,
                      decoration: const InputDecoration(),
                      onChanged: (value) => title = value,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LabeledField(
                    label: '来源编码',
                    child: DropdownButtonFormField<String>(
                      icon: const Icon(InkIcons.chevronDown, size: 12),
                      initialValue: encoding,
                      decoration: const InputDecoration(),
                      items: const [
                        DropdownMenuItem(value: 'utf-8', child: Text('UTF-8')),
                        DropdownMenuItem(
                          value: 'gb18030',
                          child: Text('GB18030'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            encoding = value;
                            decode();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        error.isEmpty ? decoded : error,
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
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: error.isNotEmpty
                    ? null
                    : () {
                        if (title.trim().isNotEmpty) {
                          Navigator.pop(dialogContext, (title.trim(), decoded));
                        }
                      },
                child: const Text('作为新章节导入'),
              ),
            ],
          ),
        ),
      );
      if (result != null) await c.createChapter(result.$1, text: result.$2);
    });

Future<void> exportText(
  BuildContext context,
  WorkbenchController c, {
  bool wholeWork = false,
}) => uiAction(context, () async {
  if (!await c.flushAll() ||
      c.work == null ||
      (!wholeWork && c.activeChapterId == null)) {
    return;
  }
  final name = wholeWork ? c.work!.manifest.title : c.activeChapter!.title;
  final location = await getSaveLocation(
    suggestedName: '${_filename(name)}.txt',
    acceptedTypeGroups: [_textType],
    confirmButtonText: '导出',
  );
  if (location == null) return;
  final target = File(location.path);
  final parent = await target.parent.resolveSymbolicLinks();
  final sourceRoot = await c.work!.root.resolveSymbolicLinks();
  if (p.equals(parent, sourceRoot) || p.isWithin(sourceRoot, parent)) {
    throw const FormatException('请将导出稿保存到作品文件夹之外，避免覆盖作品记录');
  }
  final bytes = wholeWork
      ? await TextTransfer.exportWork(c.work!)
      : await TextTransfer.exportChapter(c.work!, c.activeChapterId!);
  await writeSelectedFile(target, bytes);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('TXT 已导出')));
  }
});

Future<void> createBackup(BuildContext context, WorkbenchController c) =>
    uiAction(context, () async {
      if (!await c.flushAll() || c.work == null) return;
      final target = await getSaveLocation(
        suggestedName: '${_filename(c.work!.manifest.title)}.zip',
        acceptedTypeGroups: [_zipType],
        confirmButtonText: '保存备份',
      );
      if (target == null) return;
      await BackupService.create(c.work!, File(target.path));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('完整作品备份已保存')));
      }
    });

Future<void> restoreBackup(BuildContext context, WorkbenchController c) =>
    uiAction(context, () async {
      if (!await c.flushAll()) return;
      final source = await openFile(acceptedTypeGroups: [_zipType]);
      if (source == null) return;
      final parent = await c.services.pickWorkDirectory();
      if (parent == null) return;
      final restored = await BackupService.restore(File(source.path), parent);
      final bookmark = await c.services.bookmark(restored.root);
      await c.openWork(restored.root, bookmark: bookmark);
    });
