import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/platform/selected_file_output.dart';

// A save panel grants access to this file, not its parent or sibling files.
class SelectedFile extends Fake implements File {
  List<int>? saved;
  bool flushed = false;
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    saved = List.of(bytes);
    flushed = flush;
    return this;
  }
}

void main() {
  test(
    'macOS export only writes the file authorized by the save panel',
    () async {
      final file = SelectedFile();
      await writeSelectedFile(file, [228, 184, 173]);
      expect(file.saved, [228, 184, 173]);
      expect(file.flushed, isTrue);
    },
    skip: !Platform.isMacOS,
  );
}
