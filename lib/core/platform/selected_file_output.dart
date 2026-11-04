import 'dart:io';
import 'package:path/path.dart' as p;
import '../storage/local_file_store.dart';
import '../storage/operation_journal.dart';
import '../storage/record_store.dart';

Future<void> writeSelectedFile(File target, List<int> bytes) async {
  if (Platform.isMacOS) {
    // NSSavePanel authorizes this exact file, not sibling temporary files.
    await target.writeAsBytes(bytes, flush: true);
    return;
  }
  final store = RecordStore(LocalFileStore(target.parent));
  final name = p.basename(target.path);
  final previous = await store.read(name);
  final result = await store.write(name, bytes, expected: previous?.version);
  if (!result.isSaved) throw SaveException(result);
}
