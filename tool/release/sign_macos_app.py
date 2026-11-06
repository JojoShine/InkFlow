"""Optional Developer ID signing + notarization; unsigned CI remains buildable."""
import base64
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import plistlib


def run(*args):
    result = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode:
        raise RuntimeError(f'{args[0]} operation failed (exit {result.returncode}); inspect signing/notarization configuration')


app = Path('build/macos/Build/Products/Release/inkflow.app')
Path('dist/notarized').unlink(missing_ok=True)
required = ('MACOS_CERTIFICATE_P12', 'MACOS_CERTIFICATE_PASSWORD', 'MACOS_SIGN_IDENTITY', 'APPLE_ID', 'APPLE_APP_PASSWORD', 'APPLE_TEAM_ID')
if not all(os.environ.get(key) for key in required):
    print('Developer ID/notarization not configured; update archive signatures are handled separately')
else:
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        certificate = folder / 'certificate.p12'
        certificate.write_bytes(base64.b64decode(os.environ['MACOS_CERTIFICATE_P12'], validate=True))
        certificate.chmod(0o600)
        keychain = str(folder / 'signing.keychain-db')
        password = secrets.token_urlsafe(32)
        # Preserve login/default search list so system signing tools remain functional.
        original = subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True)
        import shlex
        original_keychains = shlex.split(original)
        try:
            run('security', 'create-keychain', '-p', password, keychain)
            run('security', 'set-keychain-settings', '-lut', '21600', keychain)
            run('security', 'unlock-keychain', '-p', password, keychain)
            run('security', 'import', str(certificate), '-k', keychain, '-P', os.environ['MACOS_CERTIFICATE_PASSWORD'], '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
            run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain)
            run('security', 'list-keychains', '-d', 'user', '-s', keychain, *original_keychains)
            identity = os.environ['MACOS_SIGN_IDENTITY']
            # Sign Mach-O code first, then enclosing bundles inside out (Sparkle
            # contains helper applications/XPC services which must retain their IDs).
            magics = (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf')
            for path in sorted(app.rglob('*')):
                if path.is_file() and not path.is_symlink():
                    with path.open('rb') as stream:
                        magic = stream.read(4)
                    if magic in magics:
                        run('codesign', '--force', '--timestamp', '--options', 'runtime', '--preserve-metadata=identifier,entitlements', '--sign', identity, str(path))
            bundles = [p for p in app.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in ('.app', '.xpc', '.framework', '.bundle')]
            for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
                run('codesign', '--force', '--timestamp', '--options', 'runtime', '--preserve-metadata=identifier,entitlements', '--sign', identity, str(bundle))
            # codesign does not expand Xcode build variables in a source plist.
            with (app / 'Contents/Info.plist').open('rb') as stream:
                bundle_id = plistlib.load(stream)['CFBundleIdentifier']
            entitlements = Path('macos/Runner/Release.entitlements').read_text().replace('$(PRODUCT_BUNDLE_IDENTIFIER)', bundle_id)
            signing_entitlements = folder / 'entitlements.plist'
            signing_entitlements.write_text(entitlements)
            run('codesign', '--force', '--timestamp', '--options', 'runtime', '--entitlements', str(signing_entitlements), '--sign', identity, str(app))
            run('codesign', '--verify', '--deep', '--strict', str(app))
            archive = folder / 'notarize.zip'
            run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive))
            run('xcrun', 'notarytool', 'submit', str(archive), '--apple-id', os.environ['APPLE_ID'], '--password', os.environ['APPLE_APP_PASSWORD'], '--team-id', os.environ['APPLE_TEAM_ID'], '--wait')
            run('xcrun', 'stapler', 'staple', str(app))
            run('xcrun', 'stapler', 'validate', str(app))
            run('spctl', '--assess', '--type', 'execute', str(app))
            Path('dist/notarized').write_text('verified')
        finally:
            run('security', 'list-keychains', '-d', 'user', '-s', *original_keychains)
            run('security', 'delete-keychain', keychain)
