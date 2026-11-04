import 'dart:io';
import 'package:path/path.dart' as p;
import 'selected_file_output.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class DesktopServices {
  static const _channel = MethodChannel('inkflow/desktop');

  Future<bool> saveShareImage(
    Uint8List bytes,
    String filename, {
    required Directory workRoot,
  }) async {
    final location = await getSaveLocation(
      suggestedName: '$filename.png',
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '分享图片',
          extensions: ['png'],
          uniformTypeIdentifiers: ['public.png'],
        ),
      ],
      confirmButtonText: '保存图片',
    );
    if (location == null) return false;
    final path = p.extension(location.path).toLowerCase() == '.png'
        ? location.path
        : '${location.path}.png';
    await writeShareImage(File(path), bytes, workRoot: workRoot);
    return true;
  }

  static Future<void> writeShareImage(
    File target,
    Uint8List bytes, {
    required Directory workRoot,
  }) async {
    final source = await workRoot.resolveSymbolicLinks();
    final parent = await target.parent.resolveSymbolicLinks();
    final resolved = await target.exists()
        ? await target.resolveSymbolicLinks()
        : p.join(parent, p.basename(target.path));
    if (p.equals(parent, source) ||
        p.isWithin(source, parent) ||
        p.equals(resolved, source) ||
        p.isWithin(source, resolved)) {
      throw const FormatException('请将分享图片保存到作品文件夹之外，避免覆盖作品记录');
    }
    for (final directory in [Directory(parent), File(resolved).parent]) {
      var ancestor = directory;
      while (true) {
        if (await File(p.join(ancestor.path, 'work.json')).exists()) {
          throw const FormatException('请将分享图片保存到作品文件夹之外，避免覆盖作品记录');
        }
        final next = ancestor.parent;
        if (p.equals(next.path, ancestor.path)) break;
        ancestor = next;
      }
    }
    await writeSelectedFile(target, bytes);
  }

  Future<Uint8List?> pickCoverImage() async {
    final image = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '封面图片',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
          uniformTypeIdentifiers: [
            'public.png',
            'public.jpeg',
            'org.webmproject.webp',
          ],
        ),
      ],
    );
    if (image == null) return null;
    if (await image.length() > 20 * 1024 * 1024) {
      throw const FormatException('请选择小于 20 MB 的封面图片');
    }
    return image.readAsBytes();
  }

  Future<Directory?> pickWorkDirectory() async {
    final path = await getDirectoryPath(confirmButtonText: '选择文件夹');
    return path == null ? null : Directory(path);
  }

  Future<String> bookmark(Directory directory) async {
    if (!Platform.isMacOS) return '';
    return await _channel.invokeMethod<String>('bookmark', directory.path) ??
        '';
  }

  Future<Directory> resolveDirectory(String path, String bookmark) async {
    if (!Platform.isMacOS || bookmark.isEmpty) return Directory(path);
    final restored = await _channel.invokeMethod<String>(
      'resolveBookmark',
      bookmark,
    );
    return Directory(restored ?? path);
  }

  Future<void> focusWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }
}
