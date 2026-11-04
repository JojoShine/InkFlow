import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../core/storage/work_key.dart';
import '../preferences/device_preferences.dart';
import '../works/work_repository.dart';

class MigrationResult {
  MigrationResult({
    required this.importedWorkCount,
    required this.importedFileCount,
    required Iterable<RecentWork> externalWorks,
    required Iterable<String> externalLibraryRoots,
    required Iterable<String> externalWallpaperPaths,
    required Iterable<String> warnings,
  }) : externalWorks = List.unmodifiable(externalWorks),
       externalLibraryRoots = List.unmodifiable(externalLibraryRoots),
       externalWallpaperPaths = List.unmodifiable(externalWallpaperPaths),
       warnings = List.unmodifiable(warnings);
  final int importedWorkCount, importedFileCount;
  final List<RecentWork> externalWorks;
  final List<String> externalLibraryRoots, externalWallpaperPaths, warnings;
}

/// Filesystem boundary so copy/commit failures can be verified deterministically.
class MigrationFileOperations {
  const MigrationFileOperations();
  Future<void> copy(File source, String destination) async {
    await source.copy(destination);
  }

  Future<void> move(FileSystemEntity source, String destination) async {
    if (source is Directory) {
      await source.rename(destination);
    } else {
      await (source as File).rename(destination);
    }
  }
}

/// The caller must authorize directory access and wait for the old app to exit.
class DataMigrationService {
  DataMigrationService({
    MigrationFileOperations files = const MigrationFileOperations(),
  }) : _files = files;
  final MigrationFileOperations _files;
  static const _stagingPrefix = '.inkflow-migration-';
  static const _receipt = 'migration-receipt.json';
  static const _runtime = {'instance.lock', 'instance.json', '.DS_Store'};

  static Future<bool> hasPersistentData(Directory target) async {
    if (!await target.exists()) return false;
    await for (final item in target.list(followLinks: false)) {
      final name = p.basename(item.path);
      if (!_runtime.contains(name) && !name.startsWith(_stagingPrefix)) {
        return true;
      }
    }
    return false;
  }

  Future<MigrationResult> importDirectory({
    required Directory source,
    required Directory target,
  }) async {
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('请选择旧版数据文件夹，不能使用目录链接');
    }
    final sourcePath = await source.resolveSymbolicLinks();
    final targetPath = await _destinationPath(target);
    if (p.equals(sourcePath, targetPath) ||
        p.isWithin(sourcePath, targetPath) ||
        p.isWithin(targetPath, sourcePath)) {
      throw const FormatException('迁移来源和目标必须是互不包含的独立目录');
    }
    final sourceRoots = {p.normalize(source.absolute.path), sourcePath};
    final before = await _inventory(Directory(sourcePath), skipRuntime: true);
    if (!before.containsKey('device-preferences.json')) {
      throw const FormatException('所选目录没有旧版设备设置，无法迁移');
    }
    final raw = jsonDecode(
      await File(p.join(sourcePath, 'device-preferences.json')).readAsString(),
    );
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('旧版设备设置损坏，原文件未改动');
    }
    try {
      DevicePreferences.fromJson(raw);
    } on TypeError {
      throw const FormatException('旧版设备设置损坏，原文件未改动');
    }
    final destination = Directory(targetPath);
    if (await hasPersistentData(destination)) {
      throw const FormatException('新版已有用户数据，不能覆盖；请保留两份数据');
    }
    await destination.create(recursive: true);
    final stage = await destination.createTemp(_stagingPrefix);
    final committed = <String, Map<String, String>>{};
    try {
      await _copyInventory(Directory(sourcePath), stage, before);
      final keys = <String, String>{}, warnings = <String>[];
      var workCount = 0;
      for (final path in before.keys.where(
        (path) => p.basename(path) == 'work.json',
      )) {
        final relativeRoot = p.dirname(path);
        final copy = await WorkRepository.open(
          Directory(p.join(stage.path, relativeRoot)),
        );
        for (final id in copy.manifest.chapterIds) {
          await copy.readChapter(id);
        }
        final cover = copy.manifest.coverFile;
        if (cover != null &&
            !await File(p.join(copy.root.path, cover)).exists()) {
          throw const FormatException('复制的作品缺少封面文件，原数据已保留');
        }
        workCount++;
        warnings.addAll(copy.issues);
        for (final oldRoot in sourceRoots) {
          keys[workKeyForPath(
            p.join(oldRoot, relativeRoot),
            copy.manifest.workId,
          )] = workKeyForPath(
            p.join(targetPath, relativeRoot),
            copy.manifest.workId,
          );
        }
      }
      String remap(String value) {
        final normalized = p.normalize(value);
        for (final root in sourceRoots) {
          if (p.equals(root, normalized)) return targetPath;
          if (p.isWithin(root, normalized)) {
            return p.join(targetPath, p.relative(normalized, from: root));
          }
        }
        return value;
      }

      final externalWorks = <String, RecentWork>{};
      for (final listName in ['recentWorks', 'trashedWorks']) {
        for (final item in (raw[listName] as List? ?? [])) {
          final entry = item as Map<String, dynamic>;
          final oldPath = entry['path'] as String,
              newPath = remap(entry['path'] as String),
              id = entry['workId'] as String;
          keys[workKeyForPath(oldPath, id)] = workKeyForPath(newPath, id);
          entry['path'] = newPath;
          entry['bookmark'] = '';
          if (newPath == oldPath) {
            externalWorks['$oldPath|$id'] = RecentWork.fromJson(entry);
          }
        }
      }
      final externalLibraries = <String>{};
      if (raw['libraryRootPath'] case final String oldPath) {
        raw['libraryRootPath'] = remap(oldPath);
        if (raw['libraryRootPath'] == oldPath) externalLibraries.add(oldPath);
      }
      raw['libraryRootBookmark'] = '';
      final externalWallpapers = <String>{};
      final appearance = raw['appearance'] as Map<String, dynamic>;
      final themes = appearance['themes'] as Map<String, dynamic>? ?? {};
      for (final value in themes.values) {
        final theme = value as Map<String, dynamic>;
        if (theme['wallpaperPath'] case final String oldPath) {
          theme['wallpaperPath'] = remap(oldPath);
          if (theme['wallpaperPath'] == oldPath) {
            externalWallpapers.add(oldPath);
          }
        }
      }
      for (final name in ['history', 'recovery']) {
        final directory = Directory(p.join(stage.path, name));
        if (!await directory.exists()) continue;
        final existing = await directory.list(followLinks: false).toList();
        for (final item in existing.whereType<Directory>()) {
          final key = p.basename(item.path),
              nextKey = keys[p.basename(item.path)];
          if (nextKey == null) {
            warnings.add('$name/$key 无法对应作品，已原样保留');
          } else if (key != nextKey) {
            final nextPath = p.join(directory.path, nextKey);
            if (await FileSystemEntity.type(nextPath, followLinks: false) !=
                FileSystemEntityType.notFound) {
              throw const FormatException('历史或恢复数据路径冲突，迁移已取消；原数据均保留');
            }
            await item.rename(nextPath);
          }
        }
      }
      await File(p.join(stage.path, 'device-preferences.json')).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
        flush: true,
      );
      if (!_same(
        before,
        await _inventory(Directory(sourcePath), skipRuntime: true),
      )) {
        throw const FormatException('旧版数据在复制期间发生变化，请退出旧版并等待同步完成后重试');
      }
      if (await hasPersistentData(destination)) {
        throw const FormatException('迁移期间目标出现了用户数据，未覆盖任何已有文件');
      }
      final fileCount = before.values
          .where((value) => value.startsWith('f:'))
          .length;
      if (externalWorks.isNotEmpty ||
          externalLibraries.isNotEmpty ||
          externalWallpapers.isNotEmpty) {
        warnings.add('旧版目录授权未沿用；请在新版重新选择外部书库、作品或壁纸');
      }
      await File(p.join(stage.path, _receipt)).writeAsString(
        jsonEncode({
          'version': 1,
          'source': sourcePath,
          'importedWorkCount': workCount,
          'importedFileCount': fileCount,
        }),
        flush: true,
      );
      final pieces = await stage.list(followLinks: false).toList();
      pieces.sort(
        (a, b) => _commitOrder(
          p.basename(a.path),
        ).compareTo(_commitOrder(p.basename(b.path))),
      );
      for (final piece in pieces) {
        final name = p.basename(piece.path),
            path = p.join(targetPath, p.basename(piece.path));
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const FormatException('目标文件已存在，迁移已停止且不会覆盖');
        }
        final inventory = piece is Directory
            ? await _inventory(piece)
            : {'': await _fingerprint(File(piece.path))};
        await _files.move(piece, path);
        committed[name] = inventory;
      }
      await stage.delete();
      return MigrationResult(
        importedWorkCount: workCount,
        importedFileCount: fileCount,
        externalWorks: externalWorks.values,
        externalLibraryRoots: externalLibraries,
        externalWallpaperPaths: externalWallpapers,
        warnings: warnings,
      );
    } catch (error, stack) {
      final retained = <String>[];
      for (final entry in committed.entries.toList().reversed) {
        final path = p.join(targetPath, entry.key);
        try {
          final type = await FileSystemEntity.type(path, followLinks: false);
          final inventory = type == FileSystemEntityType.directory
              ? await _inventory(Directory(path))
              : type == FileSystemEntityType.file
              ? {'': await _fingerprint(File(path))}
              : <String, String>{};
          if (!_same(inventory, entry.value)) {
            retained.add(path);
          } else if (type == FileSystemEntityType.directory) {
            await _files.move(Directory(path), p.join(stage.path, entry.key));
          } else {
            await _files.move(File(path), p.join(stage.path, entry.key));
          }
        } on FileSystemException {
          retained.add(path);
        } on FormatException {
          retained.add(path);
        }
      }
      try {
        if (await stage.exists()) await stage.delete(recursive: true);
      } on FileSystemException {
        retained.add(stage.path);
      }
      if (retained.isNotEmpty) {
        throw FileSystemException(
          '迁移未完成；以下目标已变化或暂不可访问，均保留未删除：${retained.join('、')}；原因：$error',
          targetPath,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  static String _commitOrder(String name) => name == _receipt
      ? '2'
      : name == 'device-preferences.json'
      ? '1'
      : '0$name';

  static Future<String> _destinationPath(Directory target) async {
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      return target.resolveSymbolicLinks();
    }
    if (type != FileSystemEntityType.notFound) {
      throw const FormatException('迁移目标必须是实际目录，不能是文件或链接');
    }
    return p.join(
      await _destinationPath(target.parent),
      p.basename(target.path),
    );
  }

  static Future<String> _fingerprint(File file) async =>
      'f:${await sha256.bind(file.openRead()).first}';

  static Future<Map<String, String>> _inventory(
    Directory root, {
    bool skipRuntime = false,
  }) async {
    final entries = <String, String>{};
    Future<void> visit(Directory directory) async {
      await for (final item in directory.list(followLinks: false)) {
        final relative = p.relative(item.path, from: root.path);
        if (skipRuntime &&
            p.dirname(relative) == '.' &&
            _runtime.contains(p.basename(relative))) {
          continue;
        }
        if (item is Directory) {
          entries[relative] = 'd';
          await visit(item);
        } else if (item is File) {
          entries[relative] = await _fingerprint(item);
        } else {
          throw const FormatException('旧数据中包含链接或特殊文件，请先导出为实际文件后再迁移');
        }
      }
    }

    await visit(root);
    return entries;
  }

  Future<void> _copyInventory(
    Directory source,
    Directory target,
    Map<String, String> inventory,
  ) async {
    for (final path in inventory.keys.toList()..sort()) {
      final destination = p.join(target.path, path);
      if (inventory[path] == 'd') {
        await Directory(destination).create(recursive: true);
      } else {
        await File(destination).parent.create(recursive: true);
        if (await FileSystemEntity.type(
              p.join(source.path, path),
              followLinks: false,
            ) !=
            FileSystemEntityType.file) {
          throw const FormatException('迁移来源已变化，未继续复制');
        }
        await _files.copy(File(p.join(source.path, path)), destination);
        if (await _fingerprint(File(destination)) != inventory[path]) {
          throw const FormatException('旧版数据在复制期间发生变化，请退出旧版后重试');
        }
      }
    }
  }

  static bool _same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);
}
