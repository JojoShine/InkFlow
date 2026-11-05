import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('configure_keys.py').resolve()

class ConfigureKeysTests(unittest.TestCase):
    def run_configuration(self, platform, required):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'macos/Runner').mkdir(parents=True)
            (root / 'windows/runner').mkdir(parents=True)
            with (root / 'macos/Runner/Info.plist').open('wb') as stream:
                plistlib.dump({}, stream)
            env = {k: v for k, v in os.environ.items() if k not in ('MACOS_ED25519_PUBLIC_KEY', 'WINDOWS_DSA_PRIVATE_KEY', 'WINDOWS_DSA_PUBLIC_KEY')}
            env.update(REQUIRE_UPDATE_KEYS='true' if required else 'false', RUNNER_TEMP=folder)
            return subprocess.run([sys.executable, str(SCRIPT), platform], cwd=root, env=env, capture_output=True, text=True)

    def test_download_only_actions_builds_do_not_require_update_keys(self):
        for platform in ('windows', 'macos'):
            self.assertEqual(self.run_configuration(platform, False).returncode, 0)

    def test_signed_actions_release_refuses_a_silently_disabled_updater(self):
        for platform in ('windows', 'macos'):
            result = self.run_configuration(platform, True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Missing update public key', result.stderr)

if __name__ == '__main__':
    unittest.main()
