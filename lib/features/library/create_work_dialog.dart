import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../core/storage/operation_journal.dart';
import '../appearance/theme_presets.dart';
import '../workbench/workbench_controller.dart';
import '../works/work_models.dart';
import '../works/work_repository.dart';
import '../../app/ink_icons.dart';
import '../../app/labeled_field.dart';
import '../preferences/device_preferences.dart';
import 'book_cover.dart';
import 'cover_image.dart';

class CreateWorkDialog extends StatefulWidget {
  const CreateWorkDialog({
    super.key,
    required this.controller,
    this.editingWork,
    this.entry,
  }) : assert((editingWork == null) == (entry == null));
  final WorkHandle? editingWork;
  final RecentWork? entry;
  final WorkbenchController controller;

  @override
  State<CreateWorkDialog> createState() => _CreateWorkDialogState();
}

class _CreateWorkDialogState extends State<CreateWorkDialog> {
  final _title = TextEditingController();
  final _synopsis = TextEditingController();
  String _audience = workAudiences.first;
  final _tags = <String>{};
  Uint8List? _cover;
  bool _coverChanged = false;
  bool get _editing => widget.editingWork != null;
  bool get _hasCover =>
      _cover != null ||
      (!_coverChanged && widget.editingWork?.manifest.coverFile != null);
  Directory? _createdRoot;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final manifest = widget.editingWork?.manifest;
    if (manifest != null) {
      _title.text = manifest.title;
      _synopsis.text = manifest.details.synopsis;
      _audience = manifest.details.audience;
      _tags.addAll(manifest.details.tags);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _synopsis.dispose();
    super.dispose();
  }

  Future<void> _chooseLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.chooseLibraryRoot();
    } on FileSystemException catch (error) {
      _error = error.message;
    } on SaveException catch (error) {
      _error = error.toString();
    } on PlatformException catch (error) {
      _error = error.message ?? '无法选择文件夹';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCover() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = await widget.controller.services.pickCoverImage();
      if (selected != null) {
        final image = await normalizeCover(selected);
        if (mounted) {
          _cover = image;
          _coverChanged = true;
        }
      }
    } on FileSystemException catch (error) {
      _error = error.message;
    } on FormatException catch (error) {
      _error = error.message;
    } on PlatformException catch (error) {
      _error = error.message ?? '无法选择封面';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (_busy || title.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = widget.controller;
      final details = WorkDetails(
        audience: _audience,
        tags: [
          for (final tag in workTagOptions)
            if (_tags.contains(tag)) tag,
          ..._tags.where((tag) => !workTagOptions.contains(tag)),
        ],
        synopsis: _synopsis.text.trim(),
      );
      if (widget.editingWork case final WorkHandle snapshot) {
        await controller.updateWorkDetails(
          widget.entry!,
          snapshot,
          title: title,
          details: details,
          cover: _cover,
          changeCover: _coverChanged,
        );
        if (mounted) Navigator.pop(context);
        return;
      }
      if (!await controller.flushAll()) {
        throw const FormatException('请先处理当前作品尚未保存的内容');
      }
      final parent = await controller.libraryDirectory();
      // Reuse this folder if an interrupted creation is retried.
      final root = _createdRoot ??= Directory(
        p.join(parent.path, 'InkFlow-${newId().substring(0, 8)}'),
      );
      final exists = await File(p.join(root.path, 'work.json')).exists();
      final work = exists
          ? await WorkRepository.open(root)
          : await WorkRepository.create(root, title, details: details);
      if (exists) await work.updateDetails(title: title, details: details);
      if (_cover != null || work.manifest.coverFile != null) {
        await work.updateCover(_cover);
      }
      if (work.manifest.chapterIds.isEmpty) await work.createChapter('第1章');
      final bookmark = await controller.services.bookmark(root);
      await controller.openWork(root, bookmark: bookmark);
      if (mounted) Navigator.pop(context);
    } on FileSystemException catch (error) {
      _error = error.message;
    } on FormatException catch (error) {
      _error = error.message;
    } on SaveException catch (error) {
      _error = error.toString();
    } on PlatformException catch (error) {
      _error = error.message ?? '无法访问作品文件夹';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    if (!_editing && widget.controller.preferences.libraryRootPath == null) {
      return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('先设置作品书库'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择或新建一个保存作品的文件夹。以后每本作品都会在这里生成独立文件夹，只需设置一次。',
                  style: TextStyle(height: 1.8),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _busy ? null : _chooseLocation,
              child: Text(_busy ? '选择中…' : '选择书库文件夹'),
            ),
          ],
        ),
      );
    }
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_editing ? '编辑作品' : '新建作品'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: _cover == null
                          ? BookCover(
                              entry: RecentWork(
                                path: widget.editingWork?.root.path ?? '',
                                workId:
                                    widget.editingWork?.manifest.workId ??
                                    'draft',
                                coverFile: _hasCover
                                    ? widget.editingWork?.manifest.coverFile
                                    : null,
                                title: _title.text.trim().isEmpty
                                    ? '新作品'
                                    : _title.text.trim(),
                              ),
                              services: widget.controller.services,
                              width: 84,
                            )
                          : Image.memory(
                              _cover!,
                              width: 84,
                              height: 126,
                              fit: BoxFit.cover,
                              cacheWidth: 168,
                            ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LabeledField(
                            label: '作品名称',
                            child: TextField(
                              key: const ValueKey('create-work-title'),
                              controller: _title,
                              autofocus: true,
                              enabled: !_busy,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: '为故事起个名字',
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: _busy ? null : _pickCover,
                                icon: const Icon(InkIcons.image, size: 16),
                                label: Text(_hasCover ? '更换封面' : '选择封面'),
                              ),
                              if (_hasCover)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _cover = null;
                                          _coverChanged = true;
                                        }),
                                  child: const Text('移除'),
                                ),
                            ],
                          ),
                          Text(
                            '封面可稍后设置',
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('目标读者', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final audience in workAudiences)
                      ChoiceChip(
                        label: Text(audience),
                        selected: _audience == audience,
                        showCheckmark: false,
                        backgroundColor: colors.paper,
                        selectedColor: colors.selection,
                        side: BorderSide(
                          color: _audience == audience
                              ? colors.accent
                              : colors.line,
                        ),
                        labelStyle: TextStyle(color: colors.ink, fontSize: 13),
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _audience = audience),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('作品标签 · 可多选', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final tag in workTagOptions)
                      FilterChip(
                        label: Text(tag),
                        selected: _tags.contains(tag),
                        showCheckmark: false,
                        backgroundColor: colors.paper,
                        selectedColor: colors.selection,
                        side: BorderSide(
                          color: _tags.contains(tag)
                              ? colors.accent
                              : colors.line,
                        ),
                        labelStyle: TextStyle(color: colors.ink, fontSize: 13),
                        onSelected: _busy
                            ? null
                            : (selected) => setState(() {
                                if (selected) {
                                  _tags.add(tag);
                                } else {
                                  _tags.remove(tag);
                                }
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                LabeledField(
                  label: '作品简介',
                  child: TextField(
                    key: const ValueKey('create-work-synopsis'),
                    controller: _synopsis,
                    enabled: !_busy,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: '写几句故事简介，会展示在书架上',
                    ),
                  ),
                ),
                if (!_editing) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(InkIcons.folder, size: 18, color: colors.muted),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('保存到书库')),
                    ],
                  ),
                  Text(
                    widget.controller.preferences.libraryRootPath!,
                    style: TextStyle(color: colors.ink, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '将自动建立作品文件夹。书库位置可在书架中更改。',
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _busy || _title.text.trim().isEmpty ? null : _create,
            child: Text(
              _busy
                  ? (_editing ? '保存中…' : '创建中…')
                  : (_editing ? '保存修改' : '创建作品'),
            ),
          ),
        ],
      ),
    );
  }
}
