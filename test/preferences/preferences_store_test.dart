import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/preferences/device_preferences.dart';
import 'package:inkflow/features/preferences/preferences_store.dart';
import 'package:inkflow/features/editor/editor_session.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('inkflow-prefs-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('theme and typography round trip independently', () async {
    final store = PreferencesStore(dir);
    await store.save(
      const DevicePreferences(
        appearance: AppearanceSettings(presetId: 'night'),
        layout: EditorLayoutSettings(fontSize: 24),
        recentWorks: [
          RecentWork(path: '/offline/作品', workId: 'work', title: '书名'),
        ],
      ),
    );
    final prefs = await PreferencesStore(dir).load();
    expect(prefs.appearance.presetId, 'night');
    expect(prefs.layout.fontSize, 24);
    expect(prefs.recentWorks.single.path, '/offline/作品');
  });
  test('corrupt preferences are preserved before defaults are used', () async {
    await File('${dir.path}/device-preferences.json').writeAsString('{broken');
    final store = PreferencesStore(dir);
    final prefs = await store.load();
    expect(prefs.appearance.presetId, 'paper');
    expect(store.warning, isNotNull);
    final preserved = await dir
        .list()
        .where((f) => f.path.contains('.corrupt-'))
        .toList();
    expect(preserved, hasLength(1));
    expect(await (preserved.single as File).readAsString(), '{broken');
  });
  test(
    'library folder and access bookmark survive appearance changes and restart',
    () async {
      final store = PreferencesStore(dir);
      final configured = const DevicePreferences(
        libraryRootPath: '/同步盘/小说书库',
        libraryRootBookmark: 'folder-permission',
      ).copyWith(appearance: const AppearanceSettings(presetId: 'night'));
      await store.save(configured);
      final restored = await PreferencesStore(dir).load();
      expect(restored.libraryRootPath, '/同步盘/小说书库');
      expect(restored.libraryRootBookmark, 'folder-permission');
      expect(restored.appearance.presetId, 'night');
      final oldData = restored.toJson()
        ..remove('libraryRootPath')
        ..remove('libraryRootBookmark');
      expect(DevicePreferences.fromJson(oldData).libraryRootPath, isNull);
    },
  );
  test('reset restores only the current theme customizations', () {
    final state = const AppearanceSettings()
        .updateCurrent(const ThemeOverrides(accentColor: 0xff000000))
        .select('night')
        .updateCurrent(const ThemeOverrides(editorOpacity: 0.8));
    final reset = state.resetCurrent();
    expect(reset.current.editorOpacity, 1);
    expect(reset.select('paper').current.accentColor, 0xff000000);
  });
}
