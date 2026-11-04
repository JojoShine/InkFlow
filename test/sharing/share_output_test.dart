import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/platform/desktop_services.dart';

void main() {
  test(
    'PNG output cannot overwrite work records or symlinks into them',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inkflow-share-output-',
      );
      try {
        final work = await Directory('${root.path}/book').create();
        final bytes = Uint8List.fromList([137, 80, 78, 71]);
        final target = File('${root.path}/excerpt.png');
        await DesktopServices.writeShareImage(target, bytes, workRoot: work);
        expect(await target.readAsBytes(), bytes);
        final record = File('${work.path}/chapter.json');
        await record.writeAsString('原稿');
        await expectLater(
          DesktopServices.writeShareImage(record, bytes, workRoot: work),
          throwsFormatException,
        );
        final alias = Link('${root.path}/alias');
        await alias.create(work.path);
        await expectLater(
          DesktopServices.writeShareImage(
            File('${alias.path}/chapter.json'),
            bytes,
            workRoot: work,
          ),
          throwsFormatException,
        );
        // A file symlink must also be resolved before the record store replaces it.
        final linkedFile = Link('${root.path}/linked.png');
        await linkedFile.create(record.path);
        await expectLater(
          DesktopServices.writeShareImage(
            File(linkedFile.path),
            bytes,
            workRoot: work,
          ),
          throwsFormatException,
        );
        final other = await Directory(
          '${root.path}/other/assets/covers',
        ).create(recursive: true);
        await File('${root.path}/other/work.json').writeAsString('{}');
        final cover = File('${other.path}/cover.png');
        await cover.writeAsString('原封面');
        await expectLater(
          DesktopServices.writeShareImage(cover, bytes, workRoot: work),
          throwsFormatException,
        );
        expect(await cover.readAsString(), '原封面');
        expect(await record.readAsString(), '原稿');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
