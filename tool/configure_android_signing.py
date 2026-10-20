"""Restore CI signing secrets without printing credentials."""

import argparse
import base64
import hashlib
import os
from pathlib import Path
import subprocess


def property_value(value):
    return (value.replace('\\', '\\\\').replace('\n', '\\n')
            .replace('\r', '\\r').replace('\t', '\\t')
            .replace('=', '\\=').replace(':', '\\:').replace(' ', '\\ '))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clean', action='store_true')
    args = parser.parse_args()
    properties = Path('android/key.properties')
    store = Path('android/signing/ci-release.p12')
    if args.clean:
        for path in (properties, store):
            path.unlink(missing_ok=True)
        return

    names = ('ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD')
    if not all(os.environ.get(name) for name in names):
        raise SystemExit('Android signing secrets missing; release cannot use debug signing')
    payload = base64.b64decode(os.environ[names[0]], validate=True)
    os.umask(0o077)
    store.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    store.write_bytes(payload)
    values = {
        'storeFile': 'signing/ci-release.p12', 'storeType': 'PKCS12',
        'storePassword': os.environ[names[1]],
        'keyAlias': os.environ[names[2]], 'keyPassword': os.environ[names[3]],
    }
    properties.write_text(''.join(f'{key}={property_value(value)}\n' for key, value in values.items()))
    for path in (store, properties):
        path.chmod(0o600)
    certificate = subprocess.run([
        'keytool', '-exportcert', '-keystore', str(store), '-storetype', 'PKCS12',
        '-alias', os.environ['ANDROID_KEY_ALIAS'], '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD',
    ], capture_output=True, check=False)
    expected = Path('android/release-certificate.sha256').read_text().strip().lower()
    if certificate.returncode or hashlib.sha256(certificate.stdout).hexdigest() != expected:
        raise SystemExit('Signing store does not match the project release certificate')
    print('Project release signing restored')


if __name__ == '__main__':
    main()
