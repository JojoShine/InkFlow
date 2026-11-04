"""Produce a sidecar only after verifying the archive against its embedded public key."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

from release import filename, read_version, sha256

parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['macos', 'windows'])
parser.add_argument('arch', choices=['arm64', 'x64'])
args = parser.parse_args()
version, build = read_version('pubspec.yaml')
artifact = Path('dist') / filename(version, build, args.platform, args.arch)
signature = ''
verified = False
notarized = False
if args.platform == 'macos':
    app = Path('build/macos/Build/Products/Release/inkflow.app')
    # Check every architecture claim against the compiled executable itself.
    expected = 'arm64' if args.arch == 'arm64' else 'x86_64'
    subprocess.run(['lipo', str(app / 'Contents/MacOS/inkflow'), '-verify_arch', expected], check=True)
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(artifact)], check=True)
    notarized = Path('dist/notarized').is_file()
    private = os.environ.get('MACOS_ED25519_PRIVATE_KEY', '').strip()
    if private:
        result = subprocess.run(['macos/Pods/Sparkle/bin/sign_update', '--ed-key-file', '-', '-p', str(artifact)], input=private + '\n', text=True, capture_output=True, check=True)
        signature = result.stdout.strip()
        with (app / 'Contents/Info.plist').open('rb') as stream:
            public = plistlib.load(stream).get('SUPublicEDKey', '')
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        Ed25519PublicKey.from_public_bytes(base64.b64decode(public, validate=True)).verify(base64.b64decode(signature, validate=True), artifact.read_bytes())
        verified = True
else:
    pfx = os.environ.get('WINDOWS_CERTIFICATE_PFX', '')
    private = os.environ.get('WINDOWS_DSA_PRIVATE_KEY', '').strip()
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        if pfx:
            certificate = folder / 'authenticode.pfx'
            certificate.write_bytes(base64.b64decode(pfx, validate=True))
            tools = sorted(Path(os.environ['ProgramFiles(x86)']).glob('Windows Kits/10/bin/*/x64/signtool.exe'), reverse=True)
            if not tools:
                raise RuntimeError('Windows SDK signtool missing')
            result = subprocess.run([str(tools[0]), 'sign', '/f', str(certificate), '/p', os.environ['WINDOWS_CERTIFICATE_PASSWORD'], '/fd', 'SHA256', '/tr', 'http://timestamp.digicert.com', '/td', 'SHA256', str(artifact)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if result.returncode:
                raise RuntimeError('Authenticode signing failed; check certificate configuration')
            subprocess.run([str(tools[0]), 'verify', '/pa', str(artifact)], check=True, stdout=subprocess.DEVNULL)
        if private:
            key = folder / 'dsa.pem'
            key.write_text(private)
            key.chmod(0o600)
            resource = Path('windows/runner/update_public_key.rc')
            # Only the resource actually used by CMake is accepted.
            import re
            public = Path(re.fullmatch(r'DSAPub DSAPEM "([^"]+)"\s*', resource.read_text()).group(1))
            digest = hashlib.sha1(artifact.read_bytes()).digest()
            # WinSparkle 0.8.1 sign_update.bat hashes the SHA1 digest a second time.
            raw = subprocess.check_output(['openssl', 'dgst', '-sha1', '-sign', str(key)], input=digest)
            sig_file = folder / 'signature.bin'
            sig_file.write_bytes(raw)
            subprocess.run(['openssl', 'dgst', '-sha1', '-verify', str(public), '-signature', str(sig_file)], input=digest, check=True, stdout=subprocess.DEVNULL)
            signature = base64.b64encode(raw).decode()
            verified = True
meta = dict(file=artifact.name, platform=args.platform, arch=args.arch, version=version, build=build, size=artifact.stat().st_size, sha256=sha256(artifact), signature=signature, verified=verified, notarized=notarized)
Path(str(artifact) + '.json').write_text(json.dumps(meta, indent=2) + '\n')
print(f'Packaged {artifact.name}; update signature verified={verified}; notarized={notarized}')
