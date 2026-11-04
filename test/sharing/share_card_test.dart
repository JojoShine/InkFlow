import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/sharing/share_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'excerpt uses complete selection or first nonempty paragraph without truncation',
    () {
      expect(
        ShareCard.excerpt(
          '\n\n第一段 👩‍💻\n第二段',
          const TextSelection.collapsed(offset: 0),
        ),
        '第一段 👩‍💻',
      );
      expect(
        ShareCard.excerpt(
          '第一段\n第二段',
          const TextSelection(baseOffset: 4, extentOffset: 7),
        ),
        '第二段',
      );
      expect(() => ShareCard.validate(' '), throwsFormatException);
      expect(
        () => ShareCard.validate(List.filled(601, '字').join()),
        throwsFormatException,
      );
      ShareCard.validate(List.filled(600, '👩‍💻').join());
    },
  );
  test(
    'excessive paragraph height is rejected explicitly without cropping',
    () async {
      await expectLater(
        ShareCard.render(
          body: List.filled(250, '字\n').join(),
          work: '书',
          chapter: '章',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'PNG keeps the full body, uses 1080 width, and grows with text in both styles',
    () async {
      for (final style in ShareCardStyle.values) {
        final short = await ShareCard.render(
          body: '一段文字。',
          work: '测试作品',
          chapter: '第一章',
          signature: '作者',
          style: style,
        );
        final long = await ShareCard.render(
          body: List.filled(20, '有一天，风把故事带到了远方。👩‍💻\n').join(),
          work: '测试作品',
          chapter: '第一章',
          style: style,
        );
        expect(short.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect(short.width, 1080);
        expect(long.height, greaterThan(short.height));
        expect(long.bodyBottom, lessThan(long.height - 90));
        final codec = await ui.instantiateImageCodec(long.bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, long.width);
        expect(frame.image.height, long.height);
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}
