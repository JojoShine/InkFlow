import 'dart:async';
import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/updates/update_controller.dart';
import 'package:inkflow/features/updates/release_manifest.dart';

class FakeUpdater implements UpdaterBackend {
  UpdaterListener? listener;
  int checks = 0;
  int? interval;
  String? feed;
  bool? background;
  bool failCheck = false;
  @override
  void addListener(UpdaterListener value) => listener = value;
  @override
  void removeListener(UpdaterListener value) => listener = null;
  @override
  Future<void> setFeedURL(String value) async => feed = value;
  @override
  Future<void> setScheduledCheckInterval(int value) async => interval = value;
  @override
  Future<void> checkForUpdates({required bool inBackground}) async {
    checks++;
    background = inBackground;
    if (failCheck) throw Exception('HTTP 404');
  }
}

void main() {
  late FakeUpdater backend;
  late UpdateController controller;
  int saves = 0, prepares = 0, quits = 0, resumes = 0;
  bool saveOK = true, prepareOK = true;
  Completer<bool>? preparation;
  setUp(() {
    backend = FakeUpdater();
    saves = prepares = quits = resumes = 0;
    saveOK = prepareOK = true;
    preparation = null;
    controller = UpdateController(
      enabled: true,
      backend: backend,
      platform: TargetPlatform.macOS,
      automaticChecks: false,
      loadAppInfo: () async => const AppInfo('墨流', '2.3.4', '27'),
      saveBeforeCheck: () async {
        saves++;
        return saveOK;
      },
      prepareForInstall: () async {
        prepares++;
        return preparation?.future ?? prepareOK;
      },
      quitAfterPrepared: () async {
        quits++;
      },
      resumeEditing: () async {
        resumes++;
      },
    );
  });
  tearDown(() => controller.dispose());

  test(
    'version comes from package metadata and debug does not auto check',
    () async {
      await controller.initialize();
      expect(controller.appInfo!.versionLabel, '2.3.4 (27)');
      expect(backend.interval, 0);
      expect(backend.checks, 0);
      expect(backend.feed, UpdateController.macosFeedURL);
    },
  );
  test('manual checks save first and duplicate requests are ignored', () async {
    await controller.checkForUpdates();
    await controller.checkForUpdates();
    expect(saves, 1);
    expect(backend.checks, 1);
    expect(backend.background, false);
    backend.listener!.onUpdaterUpdateNotAvailable(UpdaterError('No updates'));
    expect(controller.status, UpdateStatus.upToDate);
    await controller.checkForUpdates();
    expect(backend.checks, 2);
  });
  testWidgets('native check without completion times out and allows retry', (
    tester,
  ) async {
    await controller.checkForUpdates();
    expect(controller.status, UpdateStatus.checking);
    await tester.pump(const Duration(seconds: 91));
    expect(controller.status, UpdateStatus.error);
    expect(controller.message, contains('超时'));
    expect(controller.canCheck, isTrue);
    await controller.checkForUpdates();
    expect(backend.checks, 2);
    backend.listener!.onUpdaterUpdateNotAvailable(null);
  });

  testWidgets('completed native checks keep their result after the deadline', (
    tester,
  ) async {
    await controller.checkForUpdates();
    backend.listener!.onUpdaterUpdateAvailable(
      const AppcastItem(displayVersionString: '2.4'),
    );
    await tester.pump(const Duration(seconds: 91));
    expect(controller.status, UpdateStatus.available);
  });

  test('new checks immediately replace a cached failure with progress', () async {
    backend.failCheck = true;
    await controller.checkForUpdates();
    expect(controller.status, UpdateStatus.error);
    backend.failCheck = false;
    final request = controller.checkForUpdates();
    expect(controller.status, UpdateStatus.checking);
    expect(controller.message, '正在检查更新…');
    await request;
    backend.listener!.onUpdaterUpdateNotAvailable(null);
    expect(controller.status, UpdateStatus.upToDate);
  });

  test('macOS no-update completion is not overwritten by its abort callback', () async {
    await controller.checkForUpdates();
    backend.listener!.onUpdaterUpdateNotAvailable(null);
    backend.listener!.onUpdaterError(UpdaterError('No new update was found'));
    expect(controller.status, UpdateStatus.upToDate);
    backend.failCheck = true;
    await controller.checkForUpdates();
    expect(controller.status, UpdateStatus.error);
  });

  test('failed save prevents checking and allows retry', () async {
    saveOK = false;
    await controller.checkForUpdates();
    expect(backend.checks, 0);
    expect(controller.status, UpdateStatus.error);
    saveOK = true;
    await controller.checkForUpdates();
    expect(backend.checks, 1);
  });
  test('feed failure is not reported as up to date and can retry', () async {
    backend.failCheck = true;
    await controller.checkForUpdates();
    expect(controller.status, UpdateStatus.error);
    expect(controller.message, contains('暂未就绪'));
    backend.failCheck = false;
    await controller.checkForUpdates();
    expect(backend.checks, 2);
    backend.listener!.onUpdaterUpdateAvailable(
      const AppcastItem(displayVersionString: '2.4'),
    );
    expect(controller.availableVersion, '2.4');
    expect(controller.status, UpdateStatus.available);
    backend.listener!.onUpdaterUpdateDownloaded(null);
    expect(controller.status, UpdateStatus.downloaded);
  });
  test(
    'install preparation refuses quit on false and resumes editing',
    () async {
      await controller.initialize();
      prepareOK = false;
      backend.listener!.onUpdaterBeforeQuitForUpdate(null);
      await pumpEventQueue();
      expect(prepares, 1);
      expect(quits, 0);
      expect(resumes, 1);
      expect(controller.status, UpdateStatus.error);
    },
  );
  test(
    'install waits for preparation and guards duplicate native requests',
    () async {
      await controller.initialize();
      preparation = Completer<bool>();
      backend.listener!.onUpdaterBeforeQuitForUpdate(null);
      backend.listener!.onUpdaterBeforeQuitForUpdate(null);
      await pumpEventQueue();
      expect(prepares, 1);
      expect(quits, 0);
      preparation!.complete(true);
      await pumpEventQueue();
      expect(quits, 1);
      expect(resumes, 0);
      expect(controller.status, UpdateStatus.installing);
    },
  );
  test(
    'native failure during preparation resumes and cannot later quit',
    () async {
      await controller.initialize();
      preparation = Completer<bool>();
      backend.listener!.onUpdaterBeforeQuitForUpdate(null);
      await pumpEventQueue();
      backend.listener!.onUpdaterError(UpdaterError('install failed'));
      await pumpEventQueue();
      expect(resumes, 1);
      preparation!.complete(true);
      await pumpEventQueue();
      expect(quits, 0);
      expect(resumes, 1);
      expect(controller.status, UpdateStatus.error);
    },
  );
  test('disabled configuration never initializes native updater', () async {
    controller.dispose();
    controller = UpdateController(
      enabled: false,
      disabledReason: '此安装包暂不支持自动更新',
      backend: backend,
      loadAppInfo: () async => const AppInfo('墨流', '1.0', '1'),
      saveBeforeCheck: () async => true,
      prepareForInstall: () async => true,
      quitAfterPrepared: () async {},
      resumeEditing: () async {},
    );
    await controller.checkForUpdates();
    expect(backend.feed, isNull);
    expect(backend.listener, isNull);
    expect(controller.status, UpdateStatus.disabled);
    expect(controller.message, '此安装包暂不支持自动更新');
  });
  test(
    'Actions download-only packages can check releases without initializing native installation',
    () async {
      controller.dispose();
      var opened = 0;
      Uri? openedUri;
      var fail = false;
      controller = UpdateController(
        enabled: false,
        backend: backend,
        loadAppInfo: () async => const AppInfo('InkFlow', '0.1.0', '1'),
        checkPublishedRelease: () async {
          if (fail) throw const FormatException('bad manifest');
          return PublishedRelease(
            '0.2.0',
            2,
            downloadUri: Uri.parse(
              'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/releases/0.2.0/InkFlow.exe',
            ),
          );
        },
        openDownloadPage: (uri) async {
          openedUri = uri;
          opened++;
        },
        saveBeforeCheck: () async {
          saves++;
          return saveOK;
        },
        prepareForInstall: () async {
          prepares++;
          return true;
        },
        quitAfterPrepared: () async {
          quits++;
        },
        resumeEditing: () async {},
      );
      await controller.initialize();
      expect(controller.canCheck, isTrue);
      await controller.checkForUpdates();
      expect(controller.status, UpdateStatus.available);
      expect(controller.availableVersion, '0.2.0');
      expect(backend.feed, isNull);
      saveOK = false;
      await controller.downloadUpdate();
      expect(opened, 0);
      saveOK = true;
      await controller.downloadUpdate();
      expect(opened, 1);
      expect(openedUri.toString(), endsWith("/0.2.0/InkFlow.exe"));
      expect(prepares, 0);
      expect(quits, 0);
      fail = true;
      await controller.checkForUpdates();
      expect(controller.status, UpdateStatus.error);
      expect(controller.canCheck, isTrue);
    },
  );
  test(
    'signed builds use native updates even with a download fallback',
    () async {
      controller.dispose();
      controller = UpdateController(
        enabled: true,
        backend: backend,
        platform: TargetPlatform.macOS,
        automaticChecks: false,
        loadAppInfo: () async => const AppInfo('InkFlow', '0.1.0', '1'),
        checkPublishedRelease: () async => throw StateError('fallback used'),
        openDownloadPage: (_) async => fail('browser opened'),
        saveBeforeCheck: () async => true,
        prepareForInstall: () async => true,
        quitAfterPrepared: () async {},
        resumeEditing: () async {},
      );
      await controller.checkForUpdates();
      expect(controller.usesDownloadUpdates, isFalse);
      expect(controller.status, UpdateStatus.checking);
      expect(backend.feed, UpdateController.macosFeedURL);
      expect(backend.checks, 1);
    },
  );
  test('backend safety must succeed before feed initialization', () async {
    controller.dispose();
    controller = UpdateController(
      enabled: true,
      backend: backend,
      platform: TargetPlatform.windows,
      automaticChecks: false,
      loadAppInfo: () async => const AppInfo('墨流', '1.0', '1'),
      prepareBackend: () async {
        expect(backend.feed, isNull);
        return false;
      },
      saveBeforeCheck: () async => true,
      prepareForInstall: () async => true,
      quitAfterPrepared: () async {},
      resumeEditing: () async {},
    );
    await controller.initialize();
    expect(backend.feed, isNull);
    expect(controller.status, UpdateStatus.disabled);
  });

  test(
    'native install permission waits for save and cancel prevents approval',
    () async {
      await controller.initialize();
      preparation = Completer<bool>();
      final permission = controller.prepareNativeInstallation();
      final cancelled = controller.cancelNativeInstallation();
      preparation!.complete(true);
      expect(await permission, false);
      await cancelled;
      expect(quits, 0);
      expect(resumes, 1);
      expect(controller.status, UpdateStatus.error);
    },
  );

  test('native install approval leaves shutdown to native installer', () async {
    await controller.initialize();
    expect(await controller.prepareNativeInstallation(), true);
    expect(await controller.prepareNativeInstallation(), true);
    expect(prepares, 1);
    expect(quits, 0);
    await controller.cancelNativeInstallation();
    expect(resumes, 1);
  });
}
