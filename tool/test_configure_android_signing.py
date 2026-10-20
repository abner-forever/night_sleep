import base64
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import configure_android_signing


class ConfigureSigningTest(unittest.TestCase):
    def test_missing_secrets_fail_without_creating_credentials(self):
        script = Path(configure_android_signing.__file__).resolve()
        with tempfile.TemporaryDirectory() as directory:
            environment = {name: value for name, value in os.environ.items() if not name.startswith('ANDROID_KEY')}
            result = subprocess.run([sys.executable, str(script)], cwd=directory, env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(directory) / 'android/key.properties').exists())
            self.assertIn('signing secrets missing', result.stderr)

    def test_cleanup_preserves_local_signing_identity(self):
        script = Path(configure_android_signing.__file__).resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            signing = root / 'android/signing'
            signing.mkdir(parents=True)
            (signing / 'ci-release.p12').write_bytes(b'ci')
            (signing / 'night-sleep-release.p12').write_bytes(b'local')
            (root / 'android/key.properties').write_text('ci')
            subprocess.run([sys.executable, str(script), '--clean'], cwd=root, check=True)
            self.assertFalse((root / 'android/key.properties').exists())
            self.assertFalse((signing / 'ci-release.p12').exists())
            self.assertEqual((signing / 'night-sleep-release.p12').read_bytes(), b'local')

    def test_password_is_escaped_for_java_properties(self):
        self.assertEqual(configure_android_signing.property_value('a b:c=d\\e\nf'), 'a\\ b\\:c\\=d\\\\e\\nf')


if __name__ == '__main__':
    unittest.main()
