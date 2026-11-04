import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../features/works/work_models.dart';

class InstanceLease {
  InstanceLease(this.isPrimary, this._release);
  final bool isPrimary;
  final Future<void> Function() _release;
  Future<void> close() => _release();
}

class InstanceCoordinator {
  InstanceCoordinator(this.root);
  final Directory root;
  Future<InstanceLease> start({
    String? requestedPath,
    required Future<void> Function(String?) onActivate,
  }) async {
    await root.create(recursive: true);
    final file = File('${root.path}/instance.lock');
    final metadata = File('${root.path}/instance.json');
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      Map<String, dynamic>? owner;
      Socket? connected;
      for (var attempt = 0; attempt < 20; attempt++) {
        try {
          final candidate =
              jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
          if (candidate['port'] is int && candidate['token'] is String) {
            connected = await Socket.connect(InternetAddress.loopbackIPv4,
              candidate['port'] as int, timeout: const Duration(milliseconds: 250));
            owner = candidate; break;
          }
        } on FormatException {
          owner = null;
        } on FileSystemException { owner = null;
        } on SocketException { owner = null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (owner == null) throw FileSystemException('已有窗口仍在启动，请稍后重试', file.path);
      final socket = connected!;
      try {
        socket.writeln(
          jsonEncode({'token': owner['token'], 'path': requestedPath}),
        );
        await socket.flush();
        final reply = await socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 10));
        if ((jsonDecode(reply) as Map)['ok'] != true) {
          throw const FormatException('已有窗口未能处理打开请求');
        }
      } finally {
        socket.destroy();
      }
      return InstanceLease(false, () async {});
    }
    ServerSocket? server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final token = newId();
      await metadata.writeAsString(jsonEncode({'port': server.port, 'token': token}), flush: true);
      server.listen((socket) async {
        try {
          final line = await socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 3));
          final request = jsonDecode(line);
          if (request is! Map ||
              request['token'] != token ||
              (request['path'] != null && request['path'] is! String)) {
            socket.writeln('{"ok":false}');
          } else {
            await onActivate(request['path'] as String?);
            socket.writeln('{"ok":true}');
          }
          await socket.flush();
        } on FormatException {
          socket.destroy();
        } on SocketException {
          socket.destroy();
        } on TimeoutException {
          socket.destroy();
        } finally {
          await socket.close();
        }
      });
      var released = false;
      final ownedServer = server;
      return InstanceLease(true, () async {
        if (released) return;
        released = true;
        await ownedServer.close();
        await handle.unlock();
        await handle.close();
      });
    } on Object {
      await server?.close();
      await handle.unlock();
      await handle.close();
      rethrow;
    }
  }
}
