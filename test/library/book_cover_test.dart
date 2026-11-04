import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/operation_journal.dart';
import 'package:inkflow/features/library/cover_image.dart';
import 'package:inkflow/features/preferences/device_preferences.dart';
import 'package:inkflow/features/transfer/backup_service.dart';
import 'package:inkflow/features/works/work_codec.dart';
import 'package:inkflow/features/works/work_repository.dart';

final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNoSHD4DwAEpAIg90VMdgAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cover survives reopening, backup restore, replacement and removal',
    () async {
      final root = await Directory.systemTemp.createTemp('inkflow-cover-');
      addTearDown(() => root.delete(recursive: true));
      final work = await WorkRepository.create(
        Directory('${root.path}/book'),
        '春',
      );
      final chapter = await work.createChapter('第一章', text: '正文不变');
      await work.updateCover(tinyPng);
      final cover = work.manifest.coverFile!;
      expect(await File('${work.root.path}/$cover').readAsBytes(), tinyPng);
      expect((await WorkRepository.open(work.root)).manifest.coverFile, cover);
      final backup = File('${root.path}/book.zip');
      await BackupService.create(work, backup);
      final restored = await BackupService.restore(
        backup,
        Directory('${root.path}/restore'),
      );
      expect(restored.manifest.coverFile, cover);
      expect(await File('${restored.root.path}/$cover').readAsBytes(), tinyPng);
      expect(restored.manifest.workId, isNot(work.manifest.workId));
      await work.updateCover(null);
      expect((await WorkRepository.open(work.root)).manifest.coverFile, isNull);
      expect((await work.readChapter(chapter.id)).text, '正文不变');
      await work.updateCover(tinyPng);
      expect(work.manifest.coverFile, cover);
    },
  );

  test('cover changes cannot overwrite another writer’s manifest', () async {
    final root = await Directory.systemTemp.createTemp('inkflow-cover-cas-');
    addTearDown(() => root.delete(recursive: true));
    final first = await WorkRepository.create(root, '春');
    final stale = await WorkRepository.open(root);
    final chapter = await first.createChapter('保留的章节');
    await expectLater(
      stale.updateCover(tinyPng),
      throwsA(isA<SaveException>()),
    );
    expect((await WorkRepository.open(root)).manifest.chapterIds, [chapter.id]);
  });

  test('legacy manifests work and unsafe cover paths are rejected', () {
    final json = {
      'formatVersion': 1,
      'workId': 'a' * 32,
      'title': '旧作品',
      'chapterIds': <String>[],
    };
    expect(
      WorkCodec.decodeManifest(utf8.encode(jsonEncode(json))).coverFile,
      isNull,
    );
    for (final path in [
      '../cover.png',
      '/tmp/cover.png',
      'assets/covers/no.png',
    ]) {
      expect(
        () => WorkCodec.decodeManifest(
          utf8.encode(jsonEncode({...json, 'coverFile': path})),
        ),
        throwsFormatException,
      );
    }
  });

  test('view preference and cached cover preserve reading position', () {
    final entry = RecentWork(
      path: '/book',
      workId: 'a' * 32,
      title: '春',
      chapterId: 'b' * 32,
      selectionOffset: 7,
    );
    final covered = entry
        .withCover('assets/covers/${'a' * 64}.png')
        .position('b' * 32, 8, 20);
    final prefs = DevicePreferences(
      libraryView: LibraryView.cards,
      recentWorks: [covered],
    );
    final restored = DevicePreferences.fromJson(prefs.toJson());
    expect(restored.libraryView, LibraryView.cards);
    expect(restored.recentWorks.single.coverFile, covered.coverFile);
    expect(restored.recentWorks.single.selectionOffset, 8);
    final json = prefs.toJson()..remove('libraryView');
    expect(DevicePreferences.fromJson(json).libraryView, LibraryView.list);
  });

  test('image importer decodes images and rejects malformed data', () async {
    final image = await normalizeCover(tinyPng);
    expect(image.take(8), tinyPng.take(8));
    await expectLater(
      normalizeCover(utf8.encode('not an image')),
      throwsFormatException,
    );
  });

  test('large imported cover is resized before storing', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff927656), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final original = await picture.toImage(1600, 2400);
    final bytes = await original.toByteData(format: ui.ImageByteFormat.png);
    final normalized = await normalizeCover(bytes!.buffer.asUint8List());
    final codec = await ui.instantiateImageCodec(normalized);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, 800);
    expect(image.height, 1200);
    image.dispose();
    codec.dispose();
    original.dispose();
    picture.dispose();
  });

  test(
    'backup rejects a missing cover instead of creating an incomplete archive',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkflow-cover-missing-',
      );
      addTearDown(() => root.delete(recursive: true));
      final work = await WorkRepository.create(
        Directory('${root.path}/book'),
        '春',
      );
      await work.updateCover(tinyPng);
      await File('${work.root.path}/${work.manifest.coverFile}').delete();
      final destination = File('${root.path}/book.zip');
      await expectLater(
        BackupService.create(work, destination),
        throwsFormatException,
      );
      expect(await destination.exists(), isFalse);
    },
  );
}
