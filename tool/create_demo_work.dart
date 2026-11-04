import 'dart:io';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/works/work_models.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/library/demo_work.dart';

Future<void> main() async {
  final root = Directory('examples/paper-study');
  if (await File('${root.path}/work.json').exists()) { stdout.writeln(root.absolute.path); return; }
  final work = await WorkRepository.create(root, '槐花落下的时候');
  for (final title in ['第一章 旧巷', '第二章 来信', '第三章 雨停之前', '第四章 灯下', '第五章 远行', '第六章 重逢']) {
    await work.createChapter(title, text: title.startsWith('第三章') ? demoText : '在这里继续你的故事。');
  }
  var index = 0;
  for (final title in ['重读来信', '巷口重逢', '未说出口的约定']) {
    await work.saveNote(NoteRecord(id: newId(), kind: NoteKind.outline, title: title, order: index++));
  }
  await work.saveNote(NoteRecord(id: newId(), kind: NoteKind.character, title: '林晚',
    summary: '旧书店的主人，习惯在雨天整理来信。', body: '寡言，细心。始终留着一本没有写完的旅行手记。'));
  await work.saveNote(NoteRecord(id: newId(), kind: NoteKind.inspiration, title: '雨后的重逢',
    body: '让重逢从一本旧书开始。先写声音，再写她看见的人。', chapterId: work.manifest.chapterIds[2]));
  stdout.writeln(root.absolute.path);
}
