"""Inject public update keys before native compilation; private keys stay in RUNNER_TEMP."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['macos', 'windows'])
args = parser.parse_args()
required = os.environ.get('REQUIRE_UPDATE_KEYS') == 'true'
if args.platform == 'macos':
    public = os.environ.get('MACOS_ED25519_PUBLIC_KEY', '').strip()
    if required and not public:
        raise RuntimeError('Missing update public key for signed macOS release')
    path = Path('macos/Runner/Info.plist')
    with path.open('rb') as stream:
        plist = plistlib.load(stream)
    if public:
        plist['SUPublicEDKey'] = public
    with path.open('wb') as stream:
        plistlib.dump(plist, stream, sort_keys=False)
else:
    private = os.environ.get('WINDOWS_DSA_PRIVATE_KEY', '').strip()
    public = os.environ.get('WINDOWS_DSA_PUBLIC_KEY', '').strip()
    if private:
        with tempfile.TemporaryDirectory() as folder:
            key = Path(folder) / 'private.pem'
            key.write_text(private)
            key.chmod(0o600)
            public = subprocess.check_output(['openssl', 'pkey', '-in', str(key), '-pubout'], text=True)
    if required and not public:
        raise RuntimeError('Missing update public key for signed Windows release')
    if public:
        public_file = Path(os.environ['RUNNER_TEMP']) / 'inkflow-dsa-public.pem'
        public_file.write_text(public)
        Path('windows/runner/update_public_key.rc').write_text(f'DSAPub DSAPEM "{public_file.as_posix()}"\n')
