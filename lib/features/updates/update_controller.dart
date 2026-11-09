import 'dart:async';
import 'release_manifest.dart';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  const AppInfo(this.name, this.version, this.buildNumber);
  final String name, version, buildNumber;

  String get versionLabel =>
      buildNumber.isEmpty ? version : '$version ($buildNumber)';

  static Future<AppInfo> load() async {
    final info = await PackageInfo.fromPlatform();
    return AppInfo(info.appName, info.version, info.buildNumber);
  }
}

abstract interface class UpdaterBackend {
  void addListener(UpdaterListener listener);
  void removeListener(UpdaterListener listener);
  Future<void> setFeedURL(String url);
  Future<void> setScheduledCheckInterval(int seconds);
  Future<void> checkForUpdates({required bool inBackground});
}

class NativeUpdaterBackend implements UpdaterBackend {
  @override
  void addListener(UpdaterListener listener) =>
      autoUpdater.addListener(listener);
  @override
  void removeListener(UpdaterListener listener) =>
      autoUpdater.removeListener(listener);
  @override
  Future<void> setFeedURL(String url) => autoUpdater.setFeedURL(url);
  @override
  Future<void> setScheduledCheckInterval(int seconds) =>
      autoUpdater.setScheduledCheckInterval(seconds);
  @override
  Future<void> checkForUpdates({required bool inBackground}) =>
      autoUpdater.checkForUpdates(inBackground: inBackground);
}

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloaded,
  preparing,
  installing,
  error,
  disabled,
}

class UpdateController extends ChangeNotifier with UpdaterListener {
  UpdateController({
    required this.enabled,
    this.disabledReason = '此安装包暂未启用自动更新，请使用正式发布版本。',
    required this.saveBeforeCheck,
    required this.prepareForInstall,
    required this.quitAfterPrepared,
    required this.resumeEditing,
    this.prepareBackend,
    this.feedURL,
    this.checkPublishedRelease,
    this.openDownloadPage,
    UpdaterBackend? backend,
    Future<AppInfo> Function()? loadAppInfo,
    TargetPlatform? platform,
    this.automaticChecks = kReleaseMode,
  }) : _backend = backend ?? NativeUpdaterBackend(),
       _loadAppInfo = loadAppInfo ?? AppInfo.load,
       _platform = platform ?? defaultTargetPlatform;

  static const macosFeedURL = String.fromEnvironment(
    'INKFLOW_UPDATE_FEED_MACOS',
    defaultValue:
        'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/appcast-macos.xml',
  );
  static const windowsFeedURL = String.fromEnvironment(
    'INKFLOW_UPDATE_FEED_WINDOWS',
    defaultValue:
        'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/appcast-windows.xml',
  );

  final Future<bool> Function()? prepareBackend;
  final String? feedURL;
  final Future<PublishedRelease> Function()? checkPublishedRelease;
  final Future<void> Function(Uri? uri)? openDownloadPage;
  bool get usesDownloadUpdates =>
      !enabled && checkPublishedRelease != null && openDownloadPage != null;
  final bool enabled, automaticChecks;
  final String disabledReason;
  final Future<bool> Function() saveBeforeCheck, prepareForInstall;
  final Future<void> Function() quitAfterPrepared, resumeEditing;
  final UpdaterBackend _backend;
  final Future<AppInfo> Function() _loadAppInfo;
  final TargetPlatform _platform;
  AppInfo? appInfo;
  String? availableVersion;
  Uri? availableDownloadUri;
  UpdateStatus status = UpdateStatus.idle;
  String message = '可检查是否有新版本。';
  Future<void>? _initializing, _restoring;
  Future<bool>? _preparation;
  bool _nativeReady = false, _listening = false, _requesting = false;
  bool _disposed = false, _installActive = false;
  int _installGeneration = 0;
  Timer? _checkTimeout;

  bool get busy =>
      _requesting ||
      _restoring != null ||
      status == UpdateStatus.checking ||
      status == UpdateStatus.preparing ||
      status == UpdateStatus.installing;
  bool get canCheck =>
      !_disposed &&
      (enabled || usesDownloadUpdates) &&
      status != UpdateStatus.disabled &&
      !busy;

  Future<void> initialize() {
    if (_disposed || _nativeReady) return Future<void>.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    try {
      appInfo ??= await _loadAppInfo();
      if (_disposed) return;
      if (!enabled || usesDownloadUpdates) {
        _set(
          usesDownloadUpdates ? UpdateStatus.idle : UpdateStatus.disabled,
          usesDownloadUpdates ? '可检查新版本，下载后运行安装包完成更新。' : disabledReason,
        );
        return;
      }
      final feed =
          feedURL ??
          switch (_platform) {
            TargetPlatform.macOS => macosFeedURL,
            TargetPlatform.windows => windowsFeedURL,
            _ => null,
          };
      if (feed == null) {
        _set(UpdateStatus.disabled, '当前系统暂不支持应用内更新。');
        return;
      }
      final uri = Uri.tryParse(feed);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        _set(UpdateStatus.disabled, '更新设置尚未完成，请使用正式发布版本。');
        return;
      }
      if (prepareBackend != null && !await prepareBackend!()) {
        _set(UpdateStatus.disabled, '更新安装保护尚未就绪，请使用正式发布版本。');
        return;
      }
      if (_disposed) return;
      if (!_listening) {
        _backend.addListener(this);
        _listening = true;
      }
      await _backend.setFeedURL(feed);
      if (_disposed) return;
      await _backend.setScheduledCheckInterval(automaticChecks ? 86400 : 0);
      if (_disposed) return;
      _nativeReady = true;
      _notify();
      if (automaticChecks && !_requesting) {
        unawaited(_check(inBackground: true));
      }
    } catch (error) {
      if (!_disposed) _set(UpdateStatus.error, _friendlyError(error));
    }
  }

  Future<void> checkForUpdates() => _check(inBackground: false);

  Future<void> _check({required bool inBackground}) async {
    if (!_disposed && !enabled && !usesDownloadUpdates) {
      await initialize();
      return;
    }
    if (!canCheck) return;
    _requesting = true;
    availableVersion = null;
    availableDownloadUri = null;
    _set(UpdateStatus.checking, '正在检查更新…');
    try {
      await initialize();
      if (_disposed) return;
      if (usesDownloadUpdates) {
        availableVersion = null;
        availableDownloadUri = null;
        _set(UpdateStatus.checking, '正在检查更新…');
        final release = await checkPublishedRelease!();
        if (_disposed) return;
        if (release.isNewerThan(appInfo!.version, appInfo!.buildNumber)) {
          availableVersion = release.version;
          availableDownloadUri = release.downloadUri;
          _set(UpdateStatus.available, '发现新版本，可以下载安装包更新。');
        } else {
          _set(UpdateStatus.upToDate, '当前已是最新版本。');
        }
        return;
      }
      if (!_nativeReady) return;
      if (!inBackground && !await saveBeforeCheck()) {
        if (!_disposed) _set(UpdateStatus.error, '稿件尚未保存，请保存成功后重试更新。');
        return;
      }
      if (_disposed) return;
      _set(UpdateStatus.checking, '正在检查更新…');
      await _backend.checkForUpdates(inBackground: inBackground);
    } catch (error) {
      if (!_disposed) _set(UpdateStatus.error, _friendlyError(error));
    } finally {
      _requesting = false;
      _notify();
    }
  }

  Future<void> downloadUpdate() async {
    if (!usesDownloadUpdates || busy || availableVersion == null || _disposed) {
      return;
    }
    _requesting = true;
    _notify();
    try {
      if (!await saveBeforeCheck()) {
        if (!_disposed) _set(UpdateStatus.error, '稿件尚未保存，请保存成功后再前往下载。');
        return;
      }
      if (_disposed) return;
      await openDownloadPage!(availableDownloadUri);
      if (!_disposed) _set(UpdateStatus.available, '已在浏览器中打开下载，请运行安装包完成更新。');
    } catch (_) {
      if (!_disposed) {
        _set(UpdateStatus.error, '无法打开下载页，请访问 tbtparent.me/inkflow/ 下载更新。');
      }
    } finally {
      _requesting = false;
      _notify();
    }
  }

  bool get _acceptEvents => !_disposed && enabled && _listening;

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    if (_acceptEvents && !_installActive) {
      _set(UpdateStatus.checking, '正在检查更新…');
    }
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? item) {
    if (!_acceptEvents || _installActive) return;
    availableVersion = item?.displayVersionString ?? item?.versionString;
    _set(UpdateStatus.available, '发现新版本，请在系统更新窗口中选择下载与安装。');
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    // Sparkle includes its normal "no update" explanation in this event's error.
    if (_acceptEvents && !_installActive) {
      availableVersion = null;
      _set(UpdateStatus.upToDate, '当前已是最新版本。');
    }
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? item) {
    if (!_acceptEvents || _installActive) return;
    availableVersion =
        item?.displayVersionString ?? item?.versionString ?? availableVersion;
    _set(UpdateStatus.downloaded, '更新已下载，请在系统更新窗口中确认安装并重启。');
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? item) {
    if (_platform == TargetPlatform.windows ||
        !_acceptEvents ||
        _installActive ||
        _restoring != null) {
      return;
    }
    _installActive = true;
    final generation = ++_installGeneration;
    _set(UpdateStatus.preparing, '正在保存稿件，准备安装更新…');
    unawaited(_prepareAndQuit(generation));
  }

  /// Windows asks for permission before WinSparkle launches its installer.
  Future<bool> prepareNativeInstallation() async {
    if (!_acceptEvents || _restoring != null) return false;
    if (_installActive) return status == UpdateStatus.installing;
    _installActive = true;
    final generation = ++_installGeneration;
    _set(UpdateStatus.preparing, '正在保存稿件，准备安装更新…');
    try {
      final preparation = prepareForInstall();
      _preparation = preparation;
      final ready = await preparation;
      _preparation = null;
      if (_disposed || generation != _installGeneration) return false;
      if (!ready) {
        await _installationFailed('未能完成保存，已暂停安装。请确认稿件保存后重试。');
        return false;
      }
      _set(UpdateStatus.installing, '稿件已保存，正在安装更新并重启…');
      return true;
    } catch (_) {
      if (!_disposed && generation == _installGeneration) {
        await _installationFailed('未能完成更新安装，已恢复编辑。请稍后重试。');
      }
      return false;
    }
  }

  Future<void> cancelNativeInstallation() =>
      _installationFailed('更新安装已暂停，已恢复编辑。请稍后重试。');

  Future<void> _prepareAndQuit(int generation) async {
    try {
      final preparation = prepareForInstall();
      _preparation = preparation;
      final ready = await preparation;
      _preparation = null;
      if (_disposed || generation != _installGeneration) return;
      if (!ready) {
        await _installationFailed('未能完成保存，已暂停安装。请确认稿件保存后重试。');
        return;
      }
      _set(UpdateStatus.installing, '稿件已保存，正在退出以安装更新并重启…');
      await quitAfterPrepared();
    } catch (_) {
      if (!_disposed && generation == _installGeneration) {
        await _installationFailed('未能完成更新安装，已恢复编辑。请稍后重试。');
      }
    }
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    if (!_acceptEvents) return;
    // Sparkle also calls didAbortWithError(SUNoUpdateError) after reporting
    // no update. Keep that completed result until a new check starts.
    if (_platform == TargetPlatform.macOS && status == UpdateStatus.upToDate) {
      return;
    }
    if (_installActive) {
      unawaited(_installationFailed('更新安装未完成，已恢复编辑。请稍后重试。'));
    } else {
      _set(UpdateStatus.error, _friendlyError(error));
    }
  }

  Future<void> _installationFailed(String text) async {
    _installGeneration++;
    _installActive = false;
    final restoration = _restoreEditing();
    _set(UpdateStatus.error, text);
    await restoration;
  }

  Future<void> _restoreEditing() => _restoring ??=
      (() async {
        // Invalidate the workbench preparation and release its ordered native
        // lock immediately, including when an installer times out during a save.
        final preparation = _preparation;
        try {
          await resumeEditing();
        } catch (_) {
          if (!_disposed) _set(UpdateStatus.error, '恢复编辑未完成，请先检查稿件的保存状态。');
        }
        try {
          await preparation;
        } catch (_) {
          // Keep new installation attempts serialized until the old save ends.
        }
      })().whenComplete(() {
        _restoring = null;
        _notify();
      });

  String _friendlyError(Object? error) {
    final text = error.toString().toLowerCase();
    if (text.contains('404') || text.contains('not found')) {
      return '更新服务暂未就绪，请稍后重试。';
    }
    return '暂时无法检查更新，请检查网络连接后重试。';
  }

  void _set(UpdateStatus value, String text) {
    if (value == UpdateStatus.checking && enabled) {
      _checkTimeout ??= Timer(const Duration(seconds: 90), () {
        _checkTimeout = null;
        if (!_disposed && status == UpdateStatus.checking) {
          _set(UpdateStatus.error, '检查更新超时，请检查网络连接后重试。');
        }
      });
    } else {
      _checkTimeout?.cancel();
      _checkTimeout = null;
    }
    status = value;
    message = text;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _checkTimeout?.cancel();
    _disposed = true;
    _installGeneration++;
    if (_listening) _backend.removeListener(this);
    if (_installActive) unawaited(_restoreEditing());
    super.dispose();
  }
}
