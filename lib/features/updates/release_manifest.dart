import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PublishedRelease implements Comparable<PublishedRelease> {
  const PublishedRelease(this.version, this.build, {this.downloadUri});
  final String version;
  final int build;
  final Uri? downloadUri;
  static final _versionPattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  );

  static PublishedRelease parse(
    String text,
    String platform, {
    String? architecture,
  }) {
    final data = jsonDecode(text);
    if (data is! Map<String, dynamic> ||
        data['version'] is! String ||
        !_versionPattern.hasMatch(data['version'] as String) ||
        data['build'] is! int ||
        (data['build'] as int) <= 0 ||
        data['downloads'] is! List ||
        !(data['downloads'] as List).any(
          (item) => _validPackage(item, platform),
        )) {
      throw const FormatException('发布清单不完整');
    }
    final packages = (data['downloads'] as List).where(
      (item) => _validPackage(item, platform),
    );
    final matching = packages.where(
      (item) =>
          architecture == null ||
          item['arch'] == architecture ||
          item['arch'] == 'universal',
    );
    if (matching.isEmpty) throw const FormatException('当前架构暂无安装包');
    return PublishedRelease(
      data['version'] as String,
      data['build'] as int,
      downloadUri: Uri.parse(matching.first['url'] as String),
    );
  }

  static bool _validPackage(Object? item, String platform) {
    if (item is! Map ||
        item['platform'] != platform ||
        item['url'] is! String ||
        !(platform == 'windows' ? ['x64'] : ['arm64', 'x64', 'universal'])
            .contains(item['arch'])) {
      return false;
    }
    final uri = Uri.tryParse(item['url'] as String);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final bases = [
      Uri.parse(
        'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/',
      ),
    ];
    return bases.any(
          (base) => uri.origin == base.origin && uri.path.startsWith(base.path),
        ) &&
        !uri.pathSegments.any((part) => part == '..' || part.contains('\\')) &&
        (platform == 'windows'
                ? RegExp(r'\.(exe|zip)$')
                : RegExp(r'\.(zip|dmg)$'))
            .hasMatch(uri.path.toLowerCase());
  }

  @override
  int compareTo(PublishedRelease other) {
    final a = version.split('.').map(int.parse).toList();
    final b = other.version.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final comparison = a[i].compareTo(b[i]);
      if (comparison != 0) return comparison;
    }
    return build.compareTo(other.build);
  }

  bool isNewerThan(String installedVersion, String installedBuild) {
    final buildNumber = int.tryParse(installedBuild);
    if (!_versionPattern.hasMatch(installedVersion) || buildNumber == null) {
      throw const FormatException('无法读取当前版本');
    }
    return build > buildNumber &&
        compareTo(PublishedRelease(installedVersion, buildNumber)) > 0;
  }
}

class ReleaseManifestClient {
  ReleaseManifestClient({Future<String> Function(Uri)? readText})
    : _readText = readText ?? _download;
  final Future<String> Function(Uri) _readText;
  static final _source = Uri.parse(
    'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/latest.json',
  );

  Future<PublishedRelease> check(
    String platform, {
    String? architecture,
  }) async => PublishedRelease.parse(
    await _readText(_source).timeout(const Duration(seconds: 8)),
    platform,
    architecture: architecture,
  );

  static Future<String> _download(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 256 * 1024) throw const FormatException('发布清单过大');
        }
        return utf8.decode(bytes);
      })().timeout(const Duration(seconds: 8));
    } finally {
      client.close(force: true);
    }
  }
}
