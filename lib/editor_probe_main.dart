import 'package:flutter/material.dart';
import 'features/editor/editor_session.dart';
import 'features/editor/novel_editor.dart';

void main() => runApp(const EditorProbeApp());

const sampleText =
    '雨停的时候，巷子里只剩下屋檐滴水的声音。\n'
    '林晚推开木窗，潮湿的风裹着槐花的气息，轻轻落在桌上。那封信还放在原处，信封边缘已经被她摸得发软。\n'
    '她原以为，时间会让一切变得容易。可当熟悉的字迹再次出现在眼前，她才发现，有些告别从未真正发生。\n'
    '楼下传来一声自行车铃响。她抬起头，看见一个人站在巷口，肩上落着细碎的晨光。\n'
    '他没有说话，只是向她扬了扬手里的旧书。\n'
    '那一刻，她忽然想起很多年前，他们也曾在这样一个雨后的清晨，认真地约定过一次远行。';

class EditorProbeApp extends StatefulWidget {
  const EditorProbeApp({super.key});
  @override
  State<EditorProbeApp> createState() => _EditorProbeAppState();
}

class _EditorProbeAppState extends State<EditorProbeApp> {
  final session = EditorSession(text: sampleText);
  bool dark = false;
  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: dark ? const Color(0xff292622) : const Color(0xfffffdf8),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '第三章 雨停之前',
                    style: TextStyle(
                      fontFamily: 'Songti SC',
                      fontSize: 30,
                      color: dark
                          ? const Color(0xffe7ded1)
                          : const Color(0xff302c27),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => dark = !dark),
                  child: const Text('切换主题'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Expanded(
              child: NovelEditor(
                session: session,
                layout: session.layout,
                textColor: dark
                    ? const Color(0xffe7ded1)
                    : const Color(0xff302c27),
                backgroundColor: dark
                    ? const Color(0xff292622)
                    : const Color(0xfffffdf8),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
