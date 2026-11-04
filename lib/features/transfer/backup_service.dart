import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import '../../core/storage/local_file_store.dart';
import '../../core/storage/record_store.dart';
import '../../core/platform/selected_file_output.dart';
import '../works/work_repository.dart';
import '../works/work_codec.dart';
import '../works/work_models.dart';

class BackupService {
  static Future<List<File>> _sourceFiles(Directory root) async {
    final manifestFile = File(p.join(root.path, 'work.json'));
    final files = [manifestFile];
    final manifest = WorkCodec.decodeManifest(await manifestFile.readAsBytes());
    if (manifest.coverFile case final String path) {
      final cover = File(p.join(root.path, path));
      if (await FileSystemEntity.isLink(cover.path)) {
        throw const FormatException('封面必须为实际图片文件');
      }
      if (!await cover.exists()) {
        throw const FormatException('作品封面暂不可用，请等待同步或重新选择封面');
      }
      files.add(cover);
    }
    for (final path in [
      'chapters',
      'notes',
      '.inkflow/conflicts',
      '.inkflow/resolved-conflicts',
      '.inkflow/operations',
    ]) {
      final directory = Directory(p.join(root.path, path));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Link) throw const FormatException('作品中有链接文件，请先改为实际文件再备份');
        if (entity is! File || entity.path.endsWith('.tmp')) continue;
        if (entity.path.endsWith('.pending.json')) {
          throw const FormatException('作品有未完成的操作，请重新打开作品完成恢复后再备份');
        }
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static Future<void> create(WorkHandle work, File destination) async {
    final files = await _sourceFiles(work.root);
    final bytes = <String, List<int>>{};
    final hashes = <String, String>{};
    for (final file in files) {
      if (p.equals(file.absolute.path, destination.absolute.path)) {
        throw const FormatException('请将备份保存在作品文件夹之外');
      }
      final path = p
          .relative(file.path, from: work.root.path)
          .replaceAll('\\', '/');
      _validatePath(path);
      bytes[path] = await file.readAsBytes();
      hashes[path] = RecordVersion.of(bytes[path]!).hash;
    }
    final after = await _sourceFiles(work.root);
    if (after.length != files.length ||
        !after
            .map((f) => f.path)
            .toSet()
            .containsAll(files.map((f) => f.path))) {
      throw const FormatException('备份期间作品发生变化，请重试');
    }
    for (final file in after) {
      final path = p
          .relative(file.path, from: work.root.path)
          .replaceAll('\\', '/');
      if (RecordVersion.of(await file.readAsBytes()).hash != hashes[path]) {
        throw const FormatException('备份期间作品发生变化，请重试');
      }
    }
    final archive = Archive();
    for (final entry in bytes.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final index = utf8.encode(
      jsonEncode({
        'formatVersion': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'sourceWorkId': work.manifest.workId,
        'files': hashes,
      }),
    );
    archive.addFile(ArchiveFile('backup.json', index.length, index));
    final compressed = ZipEncoder().encode(archive)!;
    await writeSelectedFile(destination, compressed);
  }

  static void _validatePath(String name) {
    final parts = name.split('/');
    if (p.posix.isAbsolute(name) ||
        name.contains('\\') ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.endsWith('.') ||
              part.endsWith(' ') ||
              RegExp(r'[<>:"|?*\x00-\x1f]').hasMatch(part) ||
              RegExp(
                r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
                caseSensitive: false,
              ).hasMatch(part),
        )) {
      throw const FormatException('备份中有不安全或跨平台不兼容的文件路径');
    }
    if (name.endsWith('.pending.json')) {
      throw const FormatException('备份含有未完成操作');
    }
  }

  static Future<WorkHandle> restore(File source, Directory parent) async {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(
      await source.readAsBytes(),
      verify: true,
    );
    final seen = <String>{};
    for (final header in decoder.directory.fileHeaders) {
      final path = header.filename.replaceAll('\\', '/');
      _validatePath(
        path.endsWith('/') ? path.substring(0, path.length - 1) : path,
      );
      if (!seen.add(path.toLowerCase())) {
        throw const FormatException('备份中有重复路径');
      }
    }
    final data = <String, List<int>>{};
    for (final entry in archive) {
      if (entry.isSymbolicLink) throw const FormatException('备份中不能包含文件链接');
      if (!entry.isFile) continue;
      _validatePath(entry.name);
      data[entry.name] = List<int>.from(entry.content as List<int>);
    }
    final indexBytes = data.remove('backup.json');
    if (indexBytes == null) throw const FormatException('这不是 InkFlow 完整作品备份');
    final index = WorkCodec.object(indexBytes);
    if (index['formatVersion'] != 1 ||
        index['files'] is! Map<String, dynamic>) {
      throw const FormatException('备份格式不兼容或索引损坏');
    }
    final hashes = index['files'] as Map<String, dynamic>;
    if (hashes.length != data.length ||
        !hashes.keys.toSet().containsAll(data.keys)) {
      throw const FormatException('备份文件与索引不一致');
    }
    for (final entry in data.entries) {
      if (RecordVersion.of(entry.value).hash != hashes[entry.key]) {
        throw const FormatException('备份内容校验失败，源备份未改动');
      }
    }
    final manifestBytes = data['work.json'];
    if (manifestBytes == null) throw const FormatException('备份缺少作品清单');
    final manifest = WorkCodec.decodeManifest(manifestBytes);
    if (manifest.workId != index['sourceWorkId']) {
      throw const FormatException('备份身份与清单不一致');
    }
    for (final id in manifest.chapterIds) {
      if (!data.containsKey('chapters/$id.json') ||
          !data.containsKey('chapters/$id.txt')) {
        throw const FormatException('备份缺少章节文件');
      }
      WorkCodec.decodeChapter(data['chapters/$id.json']!);
      utf8.decode(data['chapters/$id.txt']!);
    }
    if (manifest.coverFile != null && !data.containsKey(manifest.coverFile)) {
      throw const FormatException('备份缺少封面文件');
    }
    await parent.create(recursive: true);
    final id = newId();
    final temporary = Directory(p.join(parent.path, '.inkflow-import-$id'));
    final destination = Directory(
      p.join(parent.path, 'InkFlow-restored-${id.substring(0, 8)}'),
    );
    try {
      await temporary.create();
      final files = LocalFileStore(temporary);
      for (final entry in data.entries) {
        final file = files.file(entry.key);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      await WorkRepository.open(temporary);
      final independent = WorkManifest(
        workId: newId(),
        title: manifest.title,
        details: manifest.details,
        coverFile: manifest.coverFile,
        chapterIds: manifest.chapterIds,
        volumes: manifest.volumes,
        chapterVolumes: manifest.chapterVolumes,
      );
      await files
          .file('work.json')
          .writeAsBytes(WorkCodec.encodeManifest(independent), flush: true);
      await temporary.rename(destination.path);
      return WorkRepository.open(destination);
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }
}
