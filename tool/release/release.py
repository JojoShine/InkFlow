"""Validate signed desktop artifacts, then publish to OSS. No credentials in files."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import uuid
import xml.etree.ElementTree as ET
from email.utils import format_datetime
from urllib.parse import quote

BASE = 'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/'
PREFIX = 'Download/inkflow/'
TARGETS = (('macos', 'arm64'), ('macos', 'x64'), ('windows', 'x64'))
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def read_version(pubspec, tag=None):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$', Path(pubspec).read_text(), re.M)
    if not match:
        raise ValueError('pubspec must have stable X.Y.Z+positive-build version')
    version, build = match.group(1), int(match.group(2))
    if tag is not None and tag != 'v' + version:
        raise ValueError('tag must exactly match pubspec version')
    return version, build


def filename(version, build, platform, arch):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not isinstance(build, int) or build < 1 or (platform, arch) not in TARGETS:
        raise ValueError('invalid version, build or target')
    extension = 'zip' if platform == 'macos' else 'exe'
    return f'InkFlow-{version}+{build}-{platform}-{arch}.{extension}'


def check_newer(version, build, previous):
    if previous and (build <= previous['build'] or tuple(map(int, version.split('.'))) < tuple(map(int, previous['version'].split('.')))):
        raise ValueError('release build must increase and semantic version must not decrease')


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(directory, version, build, notes, published_at):
    directory = Path(directory)
    manifest = dict(version=version, build=build, publishedAt=published_at, notes=notes, downloads=[])
    feeds = {}
    for platform, arch in TARGETS:
        name = filename(version, build, platform, arch)
        package, sidecar = directory / name, directory / (name + '.json')
        if not package.is_file() or not sidecar.is_file() or package.stat().st_size == 0:
            raise ValueError(f'missing package or signature metadata: {name}')
        meta = json.loads(sidecar.read_text())
        for key, expected in dict(file=name, platform=platform, arch=arch, version=version, build=build, size=package.stat().st_size, sha256=sha256(package), verified=True).items():
            if meta.get(key) != expected:
                raise ValueError(f'invalid {key}: {name}')
        signature = meta.get('signature', '')
        raw = base64.b64decode(signature, validate=True)
        if not raw or (platform == 'macos' and (len(raw) != 64 or not meta.get('notarized'))):
            raise ValueError(f'missing verified signature/notarization: {name}')
        url = BASE + 'releases/' + quote(f'{version}+{build}', safe='') + '/' + quote(name, safe='')
        download = dict(platform=platform, arch=arch, url=url, size=meta['size'], sha256=meta['sha256'])
        manifest['downloads'].append(download)
        rss = ET.Element('rss', version='2.0')
        channel = ET.SubElement(rss, 'channel')
        ET.SubElement(channel, 'title').text = f'InkFlow {platform} {arch}'
        ET.SubElement(channel, 'link').text = BASE
        ET.SubElement(channel, 'description').text = 'InkFlow updates'
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, 'title').text = f'InkFlow {version}'
        ET.SubElement(item, 'pubDate').text = format_datetime(datetime.fromisoformat(published_at.replace('Z', '+00:00')))
        ET.SubElement(item, 'description').text = '\n'.join(notes)
        attributes = dict(url=url, length=str(meta['size']), type='application/octet-stream')
        attributes[f'{{{NS}}}version'] = str(build)
        attributes[f'{{{NS}}}shortVersionString'] = version
        attributes[f'{{{NS}}}' + ('edSignature' if platform == 'macos' else 'dsaSignature')] = signature
        if platform == 'windows':
            attributes[f'{{{NS}}}installerArguments'] = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
        ET.SubElement(item, 'enclosure', attributes)
        feeds[f'appcast-{platform}-{arch}.xml'] = ET.tostring(rss, encoding='utf-8', xml_declaration=True)
    return manifest, feeds


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def publish(bucket, directory, manifest, feeds, site_root=None):
    """Single writer lock, immutable staging, mutable pointers, latest commit last."""
    import oss2
    if site_root:
        root = Path(site_root)
        if not (root / 'index.html').is_file() or not (root / 'website').is_dir():
            raise ValueError('site must include index.html and website directory')
        for path in [root / 'index.html', *list((root / 'website').rglob('*'))]:
            if path.is_symlink():
                raise ValueError('site must not include symbolic links')
    lock_key = PREFIX + '.release.lock'
    bucket.put_object(lock_key, uuid.uuid4().hex.encode(), headers={'x-oss-forbid-overwrite': 'true', 'Cache-Control': 'no-store'})
    try:
        def read_json(name, default):
            try:
                return json.loads(bucket.get_object(PREFIX + name).read())
            except oss2.exceptions.NoSuchKey:
                return default
        latest = read_json('latest.json', None)
        history = read_json('releases.json', {'releases': []})
        for previous in ([latest] if latest else []) + history['releases']:
            check_newer(manifest['version'], manifest['build'], previous)
        release_key = PREFIX + f"releases/{manifest['version']}+{manifest['build']}/"
        immutable = {'Cache-Control': 'public, max-age=31536000, immutable', 'x-oss-forbid-overwrite': 'true'}
        mutable = {'Cache-Control': 'no-cache, no-store, must-revalidate'}
        # Check the entire version namespace before writing anything. Partial failed
        # staging is deliberately retained for diagnosis; never overwrite it.
        if next(iter(oss2.ObjectIterator(bucket, prefix=release_key, max_keys=1)), None):
            raise ValueError('immutable version directory already exists; inspect and clean failed staging explicitly')
        for download in manifest['downloads']:
            name = filename(manifest['version'], manifest['build'], download['platform'], download['arch'])
            bucket.put_object_from_file(release_key + name, str(Path(directory) / name), headers={**immutable, 'x-oss-meta-sha256': download['sha256'], 'Content-Type': 'application/zip' if name.endswith('.zip') else 'application/vnd.microsoft.portable-executable'})
            head = bucket.head_object(release_key + name)
            if head.content_length != download['size']:
                raise ValueError('uploaded package size mismatch')
        files = {**feeds, 'release.json': json_bytes(manifest)}
        for name, data in files.items():
            bucket.put_object(release_key + name, data, headers={**immutable, 'Content-Type': 'application/json; charset=utf-8' if name.endswith('.json') else 'application/xml; charset=utf-8'})
        if site_root:
            root = Path(site_root)
            paths = [root / 'index.html', *sorted((root / 'website').rglob('*'))]
            for path in paths:
                if path.is_file():
                    import mimetypes
                    bucket.put_object_from_file(PREFIX + path.relative_to(root).as_posix(), str(path), headers={**mutable, 'Content-Type': mimetypes.guess_type(path.name)[0] or 'application/octet-stream'})
        for name, data in feeds.items():
            bucket.put_object(PREFIX + name, data, headers={**mutable, 'Content-Type': 'application/xml; charset=utf-8'})
        bucket.put_object(PREFIX + 'releases.json', json_bytes({'releases': [manifest, *history['releases']]}), headers={**mutable, 'Content-Type': 'application/json; charset=utf-8'})
        bucket.put_object(PREFIX + 'latest.json', json_bytes(manifest), headers={**mutable, 'Content-Type': 'application/json; charset=utf-8'})
    finally:
        bucket.delete_object(lock_key)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pubspec', default='pubspec.yaml')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--artifacts', default='dist')
    parser.add_argument('--notes', default='tool/release/notes.txt')
    parser.add_argument('--output', default='release-preview')
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--site-root', default='.')
    args = parser.parse_args()
    version, build = read_version(args.pubspec, args.tag)
    notes = [line.strip() for line in Path(args.notes).read_text().splitlines() if line.strip()]
    manifest, feeds = prepare(args.artifacts, version, build, notes, datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'))
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    for name, data in {**feeds, 'latest.json': json_bytes(manifest)}.items():
        (output / name).write_bytes(data)
    if args.publish:
        import oss2
        token = os.environ.get('OSS_SECURITY_TOKEN')
        auth = oss2.StsAuth(os.environ['OSS_ACCESS_KEY_ID'], os.environ['OSS_ACCESS_KEY_SECRET'], token) if token else oss2.Auth(os.environ['OSS_ACCESS_KEY_ID'], os.environ['OSS_ACCESS_KEY_SECRET'])
        bucket = oss2.Bucket(auth, 'https://oss-cn-hangzhou.aliyuncs.com', 'tbtparent-me', connect_timeout=60)
        publish(bucket, args.artifacts, manifest, feeds, args.site_root)
    print(f'Validated {version}+{build}: {len(manifest["downloads"])} signed packages')


if __name__ == '__main__':
    main()
