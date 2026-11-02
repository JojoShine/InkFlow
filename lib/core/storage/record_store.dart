import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../features/works/work_models.dart';
import 'local_file_store.dart';

class RecordVersion {
  const RecordVersion(this.hash);
  factory RecordVersion.of(List<int> bytes) =>
      RecordVersion(sha256.convert(bytes).toString());
  final String hash;
  @override
  bool operator ==(Object other) =>
      other is RecordVersion && other.hash == hash;
  @override
  int get hashCode => hash.hashCode;
}

class VersionedBytes {
  VersionedBytes(this.bytes) : version = RecordVersion.of(bytes);
  final List<int> bytes;
  final RecordVersion version;
}

enum SaveState { saved, conflict, failed }

class SaveOutcome {
  const SaveOutcome(this.state, {this.version, this.message, this.conflictId});
  final SaveState state;
  final RecordVersion? version;
  final String? message;
  final String? conflictId;
  bool get isSaved => state == SaveState.saved;
}

class RecordStore {
  RecordStore(this.files);
  final LocalFileStore files;
  final Map<String, Future<void>> _queues = {};

  Future<SaveOutcome> delete(String path, {required RecordVersion? expected}) =>
      _mutate(path, null, expected: expected);

  Future<VersionedBytes?> read(String path) async {
    if (!await files.root.exists()) {
      throw FileSystemException('作品目录不可访问', files.root.path);
    }
    final file = files.file(path);
    try {
      return VersionedBytes(await file.readAsBytes());
    } on FileSystemException catch (error) {
      if ([2, 3].contains(error.osError?.errorCode)) return null;
      rethrow;
    }
  }

  Future<SaveOutcome> write(
    String path,
    List<int> bytes, {
    required RecordVersion? expected,
  }) => _mutate(path, List<int>.of(bytes), expected: expected);

  Future<SaveOutcome> _mutate(
    String path,
    List<int>? bytes, {
    required RecordVersion? expected,
  }) {
    final result = Completer<SaveOutcome>();
    final prior = _queues[path] ?? Future<void>.value();
    final next = prior.then((_) async {
      try {
        final current = await read(path);
        final version = bytes == null ? null : RecordVersion.of(bytes);
        if (current?.version == version) {
          result.complete(SaveOutcome(SaveState.saved, version: version));
          return;
        }
        if (current?.version != expected) {
          final id = newId();
          await _atomic('.inkflow/conflicts/$id/local.bin', bytes ?? []);
          await _atomic(
            '.inkflow/conflicts/$id/external.bin',
            current?.bytes ?? [],
          );
          await _atomic(
            '.inkflow/conflicts/$id/info.json',
            utf8.encode(
              jsonEncode({
                'id': id,
                'path': path,
                'externalMissing': current == null,
                'localMissing': bytes == null,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              }),
            ),
          );
          result.complete(
            SaveOutcome(
              SaveState.conflict,
              conflictId: id,
              message: '发现外部修改，双方版本已保留',
            ),
          );
          return;
        }
        if (bytes == null) {
          await files.file(path).delete();
        } else {
          await _atomic(path, bytes);
        }
        result.complete(SaveOutcome(SaveState.saved, version: version));
      } on FileSystemException catch (error) {
        result.complete(SaveOutcome(SaveState.failed, message: error.message));
      } on FormatException catch (error) {
        result.complete(SaveOutcome(SaveState.failed, message: error.message));
      }
    });
    _queues[path] = next;
    unawaited(
      next.whenComplete(() {
        if (identical(_queues[path], next)) _queues.remove(path);
      }),
    );
    return result.future;
  }

  Future<void> _atomic(String path, List<int> bytes) async {
    if (!await files.root.exists()) {
      throw FileSystemException('作品目录不可访问', files.root.path);
    }
    final target = files.file(path);
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.${newId()}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await files.replace(temporary.path, target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
