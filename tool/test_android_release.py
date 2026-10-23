import tempfile
import unittest
from pathlib import Path

from android_release import read_version, verify_badging, verify_signature


class AndroidReleaseTest(unittest.TestCase):
    def version(self, value):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'pubspec.yaml'
            path.write_text(f'name: night_sleep\nversion: {value}\n')
            return read_version(path)

    def test_beta_and_stable_naming(self):
        beta = self.version('0.49.0-beta.1+2')
        self.assertEqual(beta['filename'], 'night-sleep-0.49.0-beta.1-android.apk')
        self.assertEqual(beta['build_number'], 2)
        self.assertEqual(beta['tag'], 'v0.49.0-beta.1')
        self.assertEqual(self.version('0.49.0+5')['channel'], 'stable')

    def test_reject_missing_or_invalid_build_number(self):
        for value in ('0.49.0', '0.49.0+0', '0.49.0-beta+2', '0.49.0-preview.1+2', '0.49.0+2100000001'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.version(value)

    def test_verify_binary_version_matches_source(self):
        metadata = self.version('0.49.0-beta.1+2')
        valid = "package: name='com.abner.night_sleep' versionCode='2' versionName='0.49.0-beta.1' platformBuildVersionName='16'\n"
        verify_badging(valid, metadata)
        for badging in (valid.replace("versionCode='2'", "versionCode='1'"),
                        valid.replace("versionName='0.49.0-beta.1'", "versionName='0.49.0'"),
                        valid.replace('com.abner.night_sleep', 'com.example.night_sleep'),
                        valid + 'application-debuggable\n', ''):
            with self.subTest(badging=badging), self.assertRaises(ValueError):
                verify_badging(badging, metadata)


    def test_accept_only_pinned_release_certificate(self):
        fingerprint = 'a' * 64
        valid = f'Number of signers: 1\nSigner #1 certificate DN: O=Night Sleep, CN=Night Sleep Android Release\nSigner #1 certificate SHA-256 digest: {fingerprint}\n'
        self.assertEqual(verify_signature(valid, fingerprint), fingerprint)
        for signature, expected in ((valid, 'b' * 64), (valid, ''),
                                    (valid.replace('Night Sleep Android Release', 'Android Debug'), fingerprint),
                                    (valid.replace('Number of signers: 1', 'Number of signers: 2'), fingerprint),
                                    (valid + f'Signer #2 certificate SHA-256 digest: {fingerprint}\n', fingerprint),
                                    ('', fingerprint)):
            with self.subTest(signature=signature, expected=expected), self.assertRaises(ValueError):
                verify_signature(signature, expected)


if __name__ == '__main__':
    unittest.main()
