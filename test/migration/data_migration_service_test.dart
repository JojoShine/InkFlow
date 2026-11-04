import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:inkflow/core/storage/work_key.dart';
import 'package:inkflow/features/migration/data_migration_service.dart';
import 'package:inkflow/features/preferences/device_preferences.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/works/work_models.dart';

class InterceptFiles extends MigrationFileOperations {
  InterceptFiles({this.onCopy, this.onMove});
  final Future<void> Function(File, String)? onCopy;
  final Future<void> Function(FileSystemEntity, String)? onMove;
  @override
  Future<void> copy(File source, String destination) async {
    await onCopy?.call(source, destination);
    await super.copy(source, destination);
  }

  @override
  Future<void> move(FileSystemEntity source, String destination) async {
    await onMove?.call(source, destination);
    await super.move(source, destination);
  }
}

void main() {
  late Directory sandbox, source, target;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('inkflow-migration-test-');
    source = await Directory(p.join(sandbox.path, 'old')).create();
    target = await Directory(p.join(sandbox.path, 'new')).create();
  });
  tearDown(() async => sandbox.delete(recursive: true));

  Future<void> preferences(Map<String, Object?> value) async => File(
    p.join(source.path, 'device-preferences.json'),
  ).writeAsString(jsonEncode(value));

  Future<Map<String, String>> tree(Directory root) async {
    final result = <String, String>{};
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is File) {
        result[p.relative(item.path, from: root.path)] = base64Encode(
          await item.readAsBytes(),
        );
      }
    }
    return result;
  }

  test(
    'copies internal works byte-for-byte and remaps only structured paths',
    () async {
      final work = await WorkRepository.create(
        Directory(p.join(source.path, 'works', 'book')),
        '原作',
        details: WorkDetails(synopsis: '简介中保留 ${source.path} 不做字符串替换'),
      );
      final chapter = await work.createChapter('第一章');
      final manuscript = utf8.encode('原稿\r\n👩‍💻\t  \r\n');
      await File(
        p.join(work.root.path, 'chapters', '${chapter.id}.txt'),
      ).writeAsBytes(manuscript);
      final oldKey = workKeyForPath(work.root.path, work.manifest.workId);
      for (final name in ['history', 'recovery']) {
        final file = File(p.join(source.path, name, oldKey, 'retained.json'));
        await file.parent.create(recursive: true);
        await file.writeAsString('原封不动的本机记录');
      }
      final unknown = File(
        p.join(source.path, 'history', 'unknown-key', 'keep.bin'),
      );
      await unknown.parent.create(recursive: true);
      await unknown.writeAsString('无法映射也保留');
      final wallpaper = File(p.join(source.path, 'wallpapers', 'paper.png'));
      await wallpaper.parent.create();
      await wallpaper.writeAsBytes([1, 2, 3]);
      final externalPath = p.join(sandbox.path, 'external', 'book');
      final external = RecentWork(
        path: externalPath,
        workId: 'e' * 32,
        title: '外部书',
        bookmark: 'old-external-permission',
      );
      final internal = RecentWork(
        path: work.root.path,
        workId: work.manifest.workId,
        title: '原作',
        bookmark: 'old-permission',
        chapterId: chapter.id,
        selectionOffset: 3,
        scrollOffset: 42,
        details: work.manifest.details,
      );
      final raw = DevicePreferences(
        recentWorks: [internal, external],
        trashedWorks: [internal],
        libraryRootPath: p.join(source.path, 'works'),
        libraryRootBookmark: 'old-library-permission',
      ).toJson();
      raw['appearance'] = {
        'presetId': 'paper',
        'animationsEnabled': false,
        'themes': {
          'paper': {'wallpaperPath': wallpaper.path},
        },
      };
      await preferences(raw);
      await File(p.join(source.path, 'instance.lock')).writeAsString('runtime');
      await File(p.join(source.path, 'instance.json')).writeAsString('runtime');
      await File(
        p.join(target.path, 'instance.lock'),
      ).writeAsString('new-runtime');
      final before = await tree(source);
      final result = await DataMigrationService().importDirectory(
        source: source,
        target: target,
      );
      expect(await tree(source), before);
      final saved =
          jsonDecode(
                await File(
                  p.join(target.path, 'device-preferences.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final loaded = DevicePreferences.fromJson(saved);
      final finalRoot = await target.resolveSymbolicLinks();
      final migratedPath = p.join(finalRoot, 'works', 'book');
      expect(loaded.recentWorks.first.path, migratedPath);
      expect(loaded.trashedWorks.single.path, migratedPath);
      expect(loaded.recentWorks.first.bookmark, isEmpty);
      expect(loaded.recentWorks.last.path, externalPath);
      expect(loaded.recentWorks.last.bookmark, isEmpty);
      expect(loaded.libraryRootBookmark, isEmpty);
      expect(loaded.libraryRootPath, p.join(finalRoot, 'works'));
      expect(
        loaded.recentWorks.first.details.synopsis,
        internal.details.synopsis,
      );
      expect(loaded.recentWorks.first.selectionOffset, 3);
      expect(loaded.recentWorks.first.scrollOffset, 42);
      expect(
        loaded.appearance.current.wallpaperPath,
        p.join(finalRoot, 'wallpapers', 'paper.png'),
      );
      expect(
        await File(
          p.join(migratedPath, 'chapters', '${chapter.id}.txt'),
        ).readAsBytes(),
        manuscript,
      );
      final newKey = workKeyForPath(migratedPath, work.manifest.workId);
      for (final name in ['history', 'recovery']) {
        expect(
          await File(
            p.join(finalRoot, name, newKey, 'retained.json'),
          ).readAsString(),
          '原封不动的本机记录',
        );
      }
      expect(
        await File(
          p.join(finalRoot, 'history', 'unknown-key', 'keep.bin'),
        ).readAsString(),
        '无法映射也保留',
      );
      expect(
        await File(p.join(target.path, 'instance.lock')).readAsString(),
        'new-runtime',
      );
      expect(
        await File(p.join(target.path, 'instance.json')).exists(),
        isFalse,
      );
      expect(result.importedWorkCount, 1);
      expect(result.externalWorks.single.path, externalPath);
    },
  );

  test(
    'requires supported preferences and never overwrites persistent target data',
    () async {
      await expectLater(
        DataMigrationService().importDirectory(source: source, target: target),
        throwsFormatException,
      );
      await preferences({'version': 999});
      await expectLater(
        DataMigrationService().importDirectory(source: source, target: target),
        throwsFormatException,
      );
      await preferences(const DevicePreferences().toJson());
      final existing = File(p.join(target.path, 'history', 'existing.txt'));
      await existing.parent.create();
      await existing.writeAsString('不能覆盖');
      await expectLater(
        DataMigrationService().importDirectory(source: source, target: target),
        throwsFormatException,
      );
      expect(await existing.readAsString(), '不能覆盖');
    },
  );

  test(
    'rejects source symlinks and nested targets without following or modifying them',
    () async {
      await preferences(const DevicePreferences().toJson());
      final outside = File(p.join(sandbox.path, 'outside.txt'));
      await outside.writeAsString('外部文件');
      await Link(p.join(source.path, 'linked')).create(outside.path);
      final before = await tree(source);
      await expectLater(
        DataMigrationService().importDirectory(source: source, target: target),
        throwsFormatException,
      );
      expect(await tree(source), before);
      expect(await outside.readAsString(), '外部文件');
      await expectLater(
        DataMigrationService().importDirectory(
          source: source,
          target: Directory(p.join(source.path, 'new')),
        ),
        throwsFormatException,
      );
      expect(await Directory(p.join(source.path, 'new')).exists(), isFalse);
    },
  );

  test(
    'validates staged works and cleans its staging after invalid copied records',
    () async {
      await preferences(const DevicePreferences().toJson());
      final invalid = File(p.join(source.path, 'works', 'broken', 'work.json'));
      await invalid.parent.create(recursive: true);
      await invalid.writeAsString('invalid work');
      final before = await tree(source);
      await expectLater(
        DataMigrationService().importDirectory(source: source, target: target),
        throwsFormatException,
      );
      expect(await tree(source), before);
      expect(await target.list().toList(), isEmpty);
    },
  );

  test(
    'a changing source is rejected and copied data is not published',
    () async {
      await preferences(const DevicePreferences().toJson());
      final changed = File(p.join(source.path, 'changed.txt'));
      await changed.writeAsString('before');
      final files = InterceptFiles(
        onCopy: (file, destination) async {
          if (p.basename(file.path) == 'device-preferences.json') {
            await changed.writeAsString('new source data');
          }
        },
      );
      await expectLater(
        DataMigrationService(
          files: files,
        ).importDirectory(source: source, target: target),
        throwsFormatException,
      );
      expect(await target.list().toList(), isEmpty);
      expect(await changed.readAsString(), 'new source data');
    },
  );

  test(
    'mid-commit collision rolls back only imported components and preserves new target files',
    () async {
      await preferences(const DevicePreferences().toJson());
      for (var i = 0; i < 2; i++) {
        final directory = await Directory(
          p.join(source.path, 'part-${i.toString().padLeft(3, '0')}'),
        ).create();
        await File(p.join(directory.path, 'data')).writeAsString('copied');
      }
      await Directory(p.join(source.path, 'zz-user')).create();
      final files = InterceptFiles(
        onMove: (entity, destination) async {
          if (p.basename(destination) == 'part-001') {
            final directory = await Directory(
              p.join(target.path, 'zz-user'),
            ).create();
            await File(
              p.join(directory.path, 'keep.txt'),
            ).writeAsString('new user data');
          }
        },
      );
      final before = await tree(source);
      await expectLater(
        DataMigrationService(
          files: files,
        ).importDirectory(source: source, target: target),
        throwsFormatException,
      );
      expect(await tree(source), before);
      expect(await tree(target), {
        'zz-user/keep.txt': base64Encode(utf8.encode('new user data')),
      });
    },
  );
}
