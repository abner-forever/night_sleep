"""Version and verify Android release artifacts without third-party dependencies."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def read_version(path):
    match = re.search(
        r'^version:\s*(\d+\.\d+\.\d+(?:-(?:beta|rc)\.[1-9]\d*)?)\+([1-9]\d*)\s*$',
        Path(path).read_text(),
        re.MULTILINE,
    )
    if not match:
        raise ValueError('pubspec version must be X.Y.Z[-beta.N|-rc.N]+BUILD')
    version, build = match.groups()
    if int(build) > 2100000000:
        raise ValueError('Android versionCode exceeds 2100000000')
    return {
        'version': version,
        'build_number': int(build),
        'channel': 'beta' if '-' in version else 'stable',
        'tag': f'v{version}',
        'filename': f'night-sleep-{version}-android.apk',
        'artifact_name': f'night-sleep-{version}-build.{build}-android',
    }


def verify_badging(badging, metadata):
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.MULTILINE)
    if not package:
        raise ValueError('APK package metadata missing')
    name, build, version = package.groups()
    if version != metadata['version'] or build != str(metadata['build_number']):
        raise ValueError('APK versionName/versionCode does not match pubspec')
    if name != 'com.example.night_sleep':
        raise ValueError('Unexpected application ID')
    if 'application-debuggable' in badging:
        raise ValueError('Release APK must not be debuggable')


def package(args, metadata):
    apk = Path(args.apk)
    badging = subprocess.check_output([args.aapt, 'dump', 'badging', str(apk)], text=True)
    verify_badging(badging, metadata)
    signature = subprocess.check_output([
        args.apksigner, 'verify', '--verbose', '--print-certs', str(apk),
    ], text=True)
    payload = apk.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    (output / metadata['filename']).write_bytes(payload)
    (output / 'package-info.txt').write_text(badging)
    (output / 'signature.txt').write_text(signature)
    (output / 'SHA256SUMS.txt').write_text(f"{digest}  {metadata['filename']}\n")
    (output / 'release.json').write_text(json.dumps({
        **metadata, 'sha256': digest, 'size': len(payload),
        'signing': 'debug', 'demo_data': False,
    }, ensure_ascii=False, indent=2) + '\n')
    (output / 'README.txt').write_text(
        f"夜深 Android {metadata['version']}（构建 {metadata['build_number']}）\n"
        '使用测试签名，非长期发布签名；演示数据关闭。\n'
        '包名暂为 com.example.night_sleep。\n'
        '助眠录音与模型授权说明请阅读仓库 README。\n'
        '尚未验证本次 APK 的真机安装、锁屏录音及升级覆盖。\n'
        'CI 重新生成测试证书时，旧包可能需先卸载；卸载会删除本地数据，请先导出。\n'
    )
    print(json.dumps({**metadata, 'sha256': digest, 'size': len(payload)}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pubspec', default='pubspec.yaml')
    commands = parser.add_subparsers(dest='command', required=True)
    version = commands.add_parser('version')
    version.add_argument('--github-output')
    artifact = commands.add_parser('package')
    artifact.add_argument('--apk', required=True)
    artifact.add_argument('--aapt', required=True)
    artifact.add_argument('--apksigner', required=True)
    artifact.add_argument('--output', default='artifacts/android')
    args = parser.parse_args()
    metadata = read_version(args.pubspec)
    if args.command == 'version':
        if args.github_output:
            with Path(args.github_output).open('a') as stream:
                for key, value in metadata.items():
                    stream.write(f'{key}={value}\n')
        print(json.dumps(metadata))
    else:
        package(args, metadata)


if __name__ == '__main__':
    main()
