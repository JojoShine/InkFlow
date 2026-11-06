import base64
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

import release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.pubspec = self.root / 'pubspec.yaml'
        self.pubspec.write_text('name: inkflow\nversion: 0.1.0+2\n')

    def package(self, platform, arch, signature=True):
        name = release.filename('0.1.0', 2, platform, arch)
        path = self.root / name
        path.write_bytes(b'full application bundle')
        meta = {'platform': platform, 'arch': arch, 'version': '0.1.0', 'build': 2,
                'file': name, 'signature': base64.b64encode(b'x' * (64 if platform == 'macos' else 48)).decode() if signature else '',
                'size': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'verified': signature, 'notarized': platform == 'macos' and signature}
        (self.root / (name + '.json')).write_text(json.dumps(meta))
        return path

    def all_packages(self):
        for platform, arch in release.TARGETS:
            self.package(platform, arch)

    def test_tag_must_match_pubspec(self):
        self.assertEqual(release.read_version(self.pubspec, 'v0.1.0'), ('0.1.0', 2))
        with self.assertRaises(ValueError):
            release.read_version(self.pubspec, 'v0.2.0')

    def test_reject_nonincrementing_build_even_with_new_version(self):
        with self.assertRaises(ValueError):
            release.check_newer('0.2.0', 2, {'version': '0.1.0', 'build': 2})
        with self.assertRaises(ValueError):
            release.check_newer('0.0.9', 3, {'version': '0.1.0', 'build': 2})
        release.check_newer('0.1.0', 3, {'version': '0.1.0', 'build': 2})

    def test_reject_missing_package_or_unsigned_feed(self):
        with self.assertRaises(ValueError):
            release.prepare(self.root, '0.1.0', 2, [], '2026-11-04T00:00:00Z')
        self.all_packages()
        self.package('windows', 'x64', signature=False)
        with self.assertRaises(ValueError):
            release.prepare(self.root, '0.1.0', 2, [], '2026-11-04T00:00:00Z')

    def test_downloads_only_accepts_unsigned_without_update_feeds(self):
        for platform, arch in release.TARGETS:
            self.package(platform, arch, signature=False)
        manifest, feeds = release.prepare(self.root, '0.1.0', 2, [],
            '2026-11-05T00:00:00Z', require_signed_updates=False)
        self.assertEqual(len(manifest['downloads']), 3)
        self.assertEqual(feeds, {})
        self.assertFalse(manifest['automaticUpdates'])

    def test_verified_update_signatures_do_not_require_apple_notarization(self):
        self.all_packages()
        for platform, arch in release.TARGETS:
            sidecar = self.root / (release.filename('0.1.0', 2, platform, arch) + '.json')
            meta = json.loads(sidecar.read_text())
            meta['notarized'] = False
            sidecar.write_text(json.dumps(meta))
        manifest, feeds = release.prepare(self.root, '0.1.0', 2, [], '2026-11-07T00:00:00Z')
        self.assertEqual(len(feeds), 3)
        self.assertTrue(manifest['automaticUpdates'])

    def test_downloads_only_still_rejects_tampered_package(self):
        for platform, arch in release.TARGETS:
            self.package(platform, arch, signature=False)
        self.package('macos', 'arm64', signature=False).write_bytes(b'tampered')
        with self.assertRaises(ValueError):
            release.prepare(self.root, '0.1.0', 2, [],
                '2026-11-05T00:00:00Z', require_signed_updates=False)

    def test_hash_tampering_rejected(self):
        self.all_packages()
        self.package('macos', 'arm64').write_bytes(b'changed after signing')
        with self.assertRaises(ValueError):
            release.prepare(self.root, '0.1.0', 2, [], '2026-11-04T00:00:00Z')

    def test_manifest_paths_and_xml_metadata(self):
        self.all_packages()
        manifest, feeds = release.prepare(self.root, '0.1.0', 2, ['A & B < C'], '2026-11-04T00:00:00Z')
        self.assertEqual(len(manifest['downloads']), 3)
        for download in manifest['downloads']:
            self.assertIn('/releases/0.1.0%2B2/', download['url'])
            self.assertEqual(download['size'], 23)
            self.assertEqual(len(download['sha256']), 64)
        ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
        for name, data in feeds.items():
            item = ET.fromstring(data).find('channel/item')
            self.assertEqual(item.findtext('description'), 'A & B < C')
            enclosure = item.find('enclosure')
            self.assertEqual(enclosure.get(ns + 'version'), '2')
            self.assertEqual(enclosure.get(ns + 'shortVersionString'), '0.1.0')
            self.assertEqual(enclosure.get('length'), '23')
            self.assertTrue(enclosure.get(ns + ('dsaSignature' if 'windows' in name else 'edSignature')))

    def test_filename_cannot_escape_version_path(self):
        with self.assertRaises(ValueError):
            release.filename('../escape', 2, 'windows', 'x64')


class PublishTests(unittest.TestCase):
    def setUp(self):
        import sys
        import types
        from unittest.mock import patch
        self.missing = type('NoSuchKey', (Exception,), {})
        sdk = types.SimpleNamespace(exceptions=types.SimpleNamespace(NoSuchKey=self.missing), ObjectIterator=lambda bucket, **kw: iter([]))
        patcher = patch.dict(sys.modules, {'oss2': sdk})
        patcher.start()
        self.addCleanup(patcher.stop)
        missing = self.missing
        class Bucket:
            def __init__(self):
                self.events = []
                self.fail_package = False
            def put_object(self, key, data, headers=None):
                self.events.append(('put', key, headers))
            def get_object(self, key):
                raise missing()
            def put_object_from_file(self, key, file, headers=None):
                self.events.append(('file', key, headers))
                if self.fail_package:
                    raise IOError('network failed')
            def head_object(self, key):
                return types.SimpleNamespace(content_length=7)
            def delete_object(self, key):
                self.events.append(('delete', key, None))
        self.bucket = Bucket()
        self.manifest = dict(version='0.1.0', build=1, downloads=[dict(platform='windows', arch='x64', size=7, sha256='a' * 64)])

    def test_failed_package_never_publishes_pointers(self):
        self.bucket.fail_package = True
        with self.assertRaises(IOError):
            release.publish(self.bucket, '.', self.manifest, {'appcast-windows-x64.xml': b'xml'})
        self.assertFalse(any(e[1].endswith(('latest.json', 'releases.json', 'appcast-windows-x64.xml')) for e in self.bucket.events))
        self.assertEqual(self.bucket.events[-1][0], 'delete')

    def test_latest_is_last_write_and_cache_policies_are_explicit(self):
        release.publish(self.bucket, '.', self.manifest, {'appcast-windows-x64.xml': b'xml'})
        writes = [e for e in self.bucket.events if e[0] != 'delete']
        self.assertTrue(writes[-1][1].endswith('/latest.json'))
        package = next(e for e in writes if e[0] == 'file')
        self.assertEqual(package[2]['x-oss-forbid-overwrite'], 'true')
        self.assertIn('immutable', package[2]['Cache-Control'])
        self.assertIn('no-cache', writes[-1][2]['Cache-Control'])

    def test_existing_lock_is_not_deleted(self):
        def locked(*args, **kwargs):
            raise IOError('lock exists')
        self.bucket.put_object = locked
        with self.assertRaises(IOError):
            release.publish(self.bucket, '.', self.manifest, {})
        self.assertEqual(self.bucket.events, [])


if __name__ == '__main__':
    unittest.main()
