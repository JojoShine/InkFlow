import 'dart:convert';
import 'dart:io';
import 'local_file_store.dart';
import 'record_store.dart';
import 'operation_journal.dart';

class SessionRecovery {
  const SessionRecovery({
    required this.chapterId,
    required this.text,
    required this.baseHash,
    this.selectionOffset = 0,
    this.scrollOffset = 0,
  });
  final String chapterId;
  final String text;
  final String baseHash;
  final int selectionOffset;
  final double scrollOffset;
}

class RecoveryStore {
  RecoveryStore(this.root);
  final Directory root;

  Future<void> writeSession(String workKey, SessionRecovery record) async {
    await root.create(recursive: true);
    final store = RecordStore(LocalFileStore(root));
    final path = 'recovery/$workKey/${record.chapterId}.json';
    final before = await store.read(path);
    final result = await store.write(
      path,
      utf8.encode(
        jsonEncode({
          'chapterId': record.chapterId,
          'text': record.text,
          'baseHash': record.baseHash,
          'selectionOffset': record.selectionOffset,
          'scrollOffset': record.scrollOffset,
        }),
      ),
      expected: before?.version,
    );
    if (!result.isSaved) throw SaveException(result);
  }

  Future<SessionRecovery?> readSession(String workKey, String chapterId) async {
    if (!await root.exists()) return null;
    final store = RecordStore(LocalFileStore(root));
    final source = await store.read('recovery/$workKey/$chapterId.json');
    if (source == null) return null;
    final json = jsonDecode(utf8.decode(source.bytes)) as Map<String, dynamic>;
    if (json['chapterId'] != chapterId ||
        json['text'] is! String ||
        json['baseHash'] is! String) {
      throw const FormatException('本机恢复记录损坏，原文件已保留');
    }
    return SessionRecovery(
      chapterId: chapterId,
      text: json['text'],
      baseHash: json['baseHash'],
      selectionOffset: json['selectionOffset'] as int? ?? 0,
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0,
    );
  }
}
