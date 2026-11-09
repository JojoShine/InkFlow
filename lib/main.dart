import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'app/inkflow_app.dart';
import 'features/workbench/workbench_controller.dart';
import 'features/updates/update_controller.dart';
import 'features/updates/release_manifest.dart';
import 'features/migration/initial_migration_dialog.dart';
import 'core/platform/instance_coordinator.dart';
import 'app/desktop_actions.dart';

InstanceLease? _instanceLease;

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final root = await getApplicationSupportDirectory();
  final controller = WorkbenchController(root);
  controller.session.addListener(() {
    if (controller.session.isUpdateLocked) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  });
  final ready = Completer<void>();
  controller.updates = await _createUpdates(controller);
  final requestedPath = arguments.isEmpty ? null : arguments.first;
  _instanceLease = await InstanceCoordinator(root).start(
    requestedPath: requestedPath,
    onActivate: (path) async {
      await ready.future;
      await controller.services.focusWindow();
      if (path != null) {
        try {
          await controller.openWork(Directory(path));
        } on FileSystemException catch (error) {
          controller.notice = error.message;
          controller.refresh();
        } on FormatException catch (error) {
          controller.notice = error.message;
          controller.refresh();
        }
      }
    },
  );
  if (!_instanceLease!.isPrimary) {
    exit(0);
  }
  final listener = _AppWindow(controller);
  windowManager.addListener(listener);
  await windowManager.setPreventClose(true);
  const lifecycle = MethodChannel('inkflow/lifecycle');
  lifecycle.setMethodCallHandler((call) async {
    if (call.method == 'requestQuit') {
      final saved = await controller.prepareToQuit();
      if (saved) await _instanceLease?.close();
      return saved;
    }
    if (call.method == 'fileAction') {
      await ready.future;
      await dispatchDesktopAction(controller, call.arguments as String);
      return true;
    }
    return null;
  });
  if (Platform.isMacOS) {
    bool? previousWorkOpen;
    controller.addListener(() {
      final open = controller.work != null;
      if (previousWorkOpen != open) {
        previousWorkOpen = open;
        lifecycle.invokeMethod<void>('setWorkOpen', open);
      }
    });
  }
  runApp(InkFlowApp(controller: controller));
  final displays = await screenRetriever.getAllDisplays();
  final cursor = await screenRetriever.getCursorScreenPoint();
  final primary = await screenRetriever.getPrimaryDisplay();
  final display = displays.firstWhere(
    (display) => ((display.visiblePosition ?? Offset.zero) & display.size)
        .contains(cursor),
    orElse: () => primary,
  );
  final available = display.visibleSize ?? display.size;
  final initialSize = Size(
    math.min(1600, available.width - 24),
    math.min(1080, available.height - 24),
  );
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: initialSize,
      minimumSize: Size(
        math.min(960, initialSize.width),
        math.min(640, initialSize.height),
      ),
      center: true,
      title: 'InkFlow',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
      // Windows accent composition washes out the native GDI manuscript.
      backgroundColor: Platform.isWindows ? null : const Color(0xfff3efe7),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  await WidgetsBinding.instance.endOfFrame;
  final context = inkFlowNavigatorKey.currentContext;
  if (context == null ||
      !context.mounted ||
      !await showInitialDataMigration(context, root)) {
    await windowManager.close();
    return;
  }
  await controller.initialize(demo: const bool.fromEnvironment('INKFLOW_DEMO'));
  unawaited(controller.updates!.initialize());
  ready.complete();
}

Future<UpdateController> _createUpdates(WorkbenchController controller) async {
  var enabled = false;
  var reason = '此安装包的更新配置尚未完成，请使用正式发布版本。';
  String? feed;
  String? architecture;
  const safety = MethodChannel('inkflow/update-safety');
  try {
    final channel = Platform.isWindows
        ? safety
        : const MethodChannel('inkflow/desktop');
    final configuration = await channel.invokeMapMethod<String, Object?>(
      Platform.isWindows ? 'configuration' : 'updateConfiguration',
    );
    enabled = configuration?['enabled'] == true;
    reason = configuration?['reason'] as String? ?? reason;
    feed = configuration?['feedURL'] as String?;
    architecture = configuration?['architecture'] as String?;
  } on MissingPluginException {
    reason = '此安装包尚未提供安全更新支持，请使用正式发布版本。';
  } on PlatformException {
    reason = '无法验证此安装包的更新配置，请使用正式发布版本。';
  }
  late final UpdateController updates;
  updates = UpdateController(
    enabled: enabled,
    disabledReason: reason,
    feedURL: feed,
    checkPublishedRelease: () => ReleaseManifestClient().check(
      Platform.isWindows ? 'windows' : 'macos',
      architecture: architecture,
    ),
    openDownloadPage: (uri) async {
      await (Platform.isWindows
              ? safety
              : const MethodChannel('inkflow/desktop'))
          .invokeMethod<void>('openDownloadPage', uri?.toString());
    },
    saveBeforeCheck: controller.flushAll,
    prepareForInstall: controller.prepareForUpdate,
    resumeEditing: controller.resumeAfterUpdate,
    quitAfterPrepared: () async {
      await _instanceLease?.close();
      await const MethodChannel(
        'inkflow/lifecycle',
      ).invokeMethod<void>('allowQuit');
      await windowManager.destroy();
    },
    prepareBackend: Platform.isWindows
        ? () async {
            safety.setMethodCallHandler((call) async {
              if (call.method == 'prepareToInstall') {
                return updates.prepareNativeInstallation();
              }
              if (call.method == 'resumeEditing') {
                await updates.cancelNativeInstallation();
              }
              return null;
            });
            return await safety.invokeMethod<bool>('configure') == true;
          }
        : null,
  );
  return updates;
}

class _AppWindow with WindowListener {
  _AppWindow(this.controller);
  final WorkbenchController controller;
  bool _closing = false;
  @override
  void onWindowFocus() {
    unawaited(controller.checkExternal());
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      if (await controller.prepareToQuit()) {
        if (Platform.isMacOS) {
          await const MethodChannel(
            'inkflow/lifecycle',
          ).invokeMethod<void>('allowQuit');
        }
        await _instanceLease?.close();
        await windowManager.destroy();
        return;
      }
    } catch (_) {
      try {
        await controller.resumeAfterUpdate();
      } catch (_) {
        controller.notice = '恢复编辑未完成，请先检查稿件的保存状态。';
        controller.refresh();
      }
    }
    _closing = false;
    await windowManager.focus();
  }
}
