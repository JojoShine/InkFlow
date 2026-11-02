import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/works/work_codec.dart';

void main() {
  const a = '0123456789abcdef0123456789abcdef';
  const b = 'fedcba9876543210fedcba9876543210';
  Map<String, Object> fixture() => {
    'formatVersion': 1,
    'workId': a,
    'title': '雨后的书房',
    'chapterIds': [b, a],
  };
  test('manifest round trip preserves explicit chapter order', () {
    final work = WorkCodec.decodeManifest(utf8.encode(jsonEncode(fixture())));
    expect(work.title, '雨后的书房');
    expect(work.chapterIds, [b, a]);
    final data = jsonDecode(utf8.decode(WorkCodec.encodeManifest(work)));
    expect(data, fixture());
  });
  test('duplicate chapter ids are rejected', () {
    final data = fixture()..['chapterIds'] = [a, a];
    expect(
      () => WorkCodec.decodeManifest(utf8.encode(jsonEncode(data))),
      throwsFormatException,
    );
  });
  test('unsafe ids and unknown format version are rejected', () {
    for (final change in [
      {'workId': '../outside'},
      {'formatVersion': 2},
      {'title': 10},
    ]) {
      expect(
        () => WorkCodec.decodeManifest(
          utf8.encode(jsonEncode({...fixture(), ...change})),
        ),
        throwsFormatException,
      );
    }
  });
}
