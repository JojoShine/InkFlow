import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/word_count.dart';

void main() {
  test('counts visible grapheme clusters including punctuation', () {
    expect(countWords('你 好\n，👨‍👩‍👧‍👦'), 4);
    expect(countWords('e\u0301'), 1);
    expect(countWords(' \n\r\t\u3000'), 0);
    expect(countWords('𠮷野家'), 3);
  });
}
