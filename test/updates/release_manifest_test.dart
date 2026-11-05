import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/updates/release_manifest.dart';

String manifest(String version, int build) => jsonEncode({
  'version': version,
  'build': build,
  'downloads': [
    {
      'platform': 'windows',
      'arch': 'x64',
      'url':
          'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/releases/$version/InkFlow.exe',
    },
  ],
});
void main() {
  test(
    'OSS is authoritative even when the website advertises a different version',
    () async {
      final client = ReleaseManifestClient(
        readText: (uri) async => manifest(
          uri.host == 'tbtparent.me' ? '9.0.0' : '0.2.0',
          uri.host == 'tbtparent.me' ? 99 : 2,
        ),
      );
      final release = await client.check('windows');
      expect(release.version, '0.2.0');
      expect(release.isNewerThan('0.1.0', '1'), isTrue);
      expect(release.isNewerThan('0.2.0', '2'), isFalse);
      expect(release.isNewerThan('0.3.0', '3'), isFalse);
    },
  );
  test(
    'network and malformed manifests cannot be reported as up to date',
    () async {
      final client = ReleaseManifestClient(readText: (_) async => '{broken');
      await expectLater(
        client.check('windows'),
        throwsA(isA<FormatException>()),
      );
    },
  );
  test('a manifest without a trusted Windows package is rejected', () {
    final json = jsonDecode(manifest('0.2.0', 2)) as Map<String, dynamic>;
    (json['downloads'] as List).first['url'] =
        'https://example.com/untrusted.exe';
    expect(
      () => PublishedRelease.parse(jsonEncode(json), 'windows'),
      throwsA(isA<FormatException>()),
    );
  });
  test('the matching architecture package is returned for direct OSS download', () {
    final data = jsonDecode(manifest('0.2.0', 2)) as Map<String, dynamic>;
    data['downloads'] = [
      {
        'platform': 'macos',
        'arch': 'arm64',
        'url':
            'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/releases/0.2.0/arm64.zip',
      },
      {
        'platform': 'macos',
        'arch': 'x64',
        'url':
            'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/releases/0.2.0/x64.zip',
      },
    ];
    final release = PublishedRelease.parse(
      jsonEncode(data),
      'macos',
      architecture: 'x64',
    );
    expect(release.downloadUri.toString(), endsWith('/x64.zip'));
    expect(
      () => PublishedRelease.parse(
        jsonEncode(data),
        'macos',
        architecture: 'unsupported',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
