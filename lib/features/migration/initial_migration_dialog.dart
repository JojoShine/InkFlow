import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import '../../core/platform/desktop_services.dart';
import '../preferences/device_preferences.dart';
import '../preferences/preferences_store.dart';
import 'data_migration_service.dart';

/// Runs before preferences or any previous manuscript are opened under the new ID.
Future<bool> showInitialDataMigration(
  BuildContext context,
  Directory root,
) async {
  if (!Platform.isMacOS) return true;
  const channel = MethodChannel('inkflow/desktop');
  final identity = await channel.invokeMapMethod<String, dynamic>(
    'applicationIdentity',
  );
  if (identity?['bundleIdentifier'] != 'me.tbtparent.inkflow' ||
      await DataMigrationService.hasPersistentData(root)) {
    return true;
  }
  if (!context.mounted) return false;
  var busy = false;
  var imported = false;
  String? message;
  MigrationResult? migration;
  Future<void> authorizeLibrary() async {
    final store = PreferencesStore(root);
    final preferences = await store.load();
    final expected = preferences.libraryRootPath;
    if (expected == null) return;
    final selected = await getDirectoryPath(
      initialDirectory: expected,
      confirmButtonText: '授权原书库',
    );
    if (selected == null) return;
    if (!p.equals(p.normalize(selected), p.normalize(expected))) {
      throw const FormatException('请选择原来的书库文件夹；作品没有移动。');
    }
    final services = DesktopServices();
    Future<List<RecentWork>> authorize(List<RecentWork> works) async {
      final result = <RecentWork>[];
      for (final work in works) {
        if (p.equals(selected, work.path) || p.isWithin(selected, work.path)) {
          final json = work.toJson();
          json['bookmark'] = await services.bookmark(Directory(work.path));
          result.add(RecentWork.fromJson(Map<String, dynamic>.from(json)));
        } else {
          result.add(work);
        }
      }
      return result;
    }

    await store.save(
      preferences.copyWith(
        libraryRootBookmark: await services.bookmark(Directory(selected)),
        recentWorks: await authorize(preferences.recentWorks),
        trashedWorks: await authorize(preferences.trashedWorks),
      ),
    );
  }

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) {
            Future<void> perform(Future<void> Function() action) async {
              setState(() {
                busy = true;
                message = null;
              });
              try {
                await action();
              } on FormatException catch (error) {
                message = error.message;
              } on FileSystemException catch (_) {
                message = '暂时无法读取数据，请确认文件夹可访问后重试。';
              } on PlatformException catch (error) {
                message = error.message ?? '目录授权未完成，请重试。';
              } finally {
                if (context.mounted) setState(() => busy = false);
              }
            }

            Future<void> requireOldAppClosed() async {
              if (await channel.invokeMethod<bool>('legacyAppRunning') ==
                  true) {
                throw const FormatException('请先在旧版 InkFlow 中保存并正常退出，再继续。');
              }
            }

            return PopScope(
              canPop: !busy,
              child: AlertDialog(
                title: Text(imported ? '旧版数据已导入' : '欢迎来到 InkFlow'),
                content: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        imported
                            ? '作品与写作记录已复制到新版，旧版数据仍然保留。'
                            : '为你的故事准备一间书房。首次使用可直接开始；已经使用过旧版，也可以一起带上作品、外观与写作记录。',
                      ),
                      if (imported &&
                          (migration?.externalWorks.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '外部书库需要重新授权。请选择原书库文件夹；零散保存的作品也可稍后通过“打开作品文件夹”重新授权。',
                        ),
                        if (migration!.externalLibraryRoots.isNotEmpty)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => perform(() async {
                                    await authorizeLibrary();
                                    message = '书库授权已更新，可以继续写作。';
                                  }),
                            child: const Text('重新授权原书库'),
                          ),
                      ],
                      if (message != null) ...[
                        const SizedBox(height: 16),
                        Text(message!),
                      ],
                      if (busy) ...[
                        const SizedBox(height: 20),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
                actions: [
                  if (!imported)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => perform(() async {
                              await requireOldAppClosed();
                              final source = await channel.invokeMethod<String>(
                                'pickLegacyDataDirectory',
                              );
                              if (source == null) return;
                              migration = await DataMigrationService()
                                  .importDirectory(
                                    source: Directory(source),
                                    target: root,
                                  );
                              imported = true;
                            }),
                      child: const Text('导入旧版数据'),
                    ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => perform(() async {
                            await requireOldAppClosed();
                            if (!imported) {
                              await PreferencesStore(
                                root,
                              ).save(const DevicePreferences());
                            }
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          }),
                    child: Text(imported ? '进入书房' : '初次使用，开始写作'),
                  ),
                ],
              ),
            );
          },
        ),
      ) ??
      false;
}
