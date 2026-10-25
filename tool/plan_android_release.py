"""Plan and publish serialized Android releases for the beta and main branches."""

import argparse
import json
from pathlib import Path
import re
import subprocess

from android_release import read_version, write_version


VERSION = re.compile(r'^v?(\d+)\.(\d+)\.(\d+)(?:-(preview|beta|rc)\.([1-9]\d*))?$')
MARKER = re.compile(r'<!-- night-sleep-release (\{[^\n]+\}) -->')
CHANGE_NOISE = re.compile(r'^(?:chore|docs|test|ci|build)(?:\(|:|$)')
CHANGE_LIMIT = 30


def version_parts(value):
    match = VERSION.fullmatch(value)
    if not match:
        return None
    return tuple(map(int, match.group(1, 2, 3))), match[4], int(match[5] or 0)


def release_marker(release):
    match = MARKER.search(release.get('body') or '')
    if not match:
        return None
    metadata = json.loads(match[1])
    if metadata.get('version') != release['tag_name'].removeprefix('v'):
        raise ValueError('Release marker version does not match tag')
    if not re.fullmatch(r'[a-f0-9]{40}', metadata.get('source_sha', '')):
        raise ValueError('Release marker source commit is invalid')
    if type(metadata.get('build_number')) is not int or metadata['build_number'] <= 0:
        raise ValueError('Release marker build number is invalid')
    branch = metadata.get('branch')
    if branch not in {'beta', 'main'} or (branch == 'beta') != bool(version_parts(metadata['version'])[1]):
        raise ValueError('Release marker branch does not match version channel')
    return metadata


def gh(*arguments):
    return subprocess.check_output(['gh', *arguments], text=True)


def load_releases(repository):
    pages = json.loads(gh('api', '--paginate', '--slurp', f'repos/{repository}/releases?per_page=100'))
    releases = [release for page in pages for release in page if version_parts(release['tag_name'])]
    for release in releases:
        metadata = release_marker(release)
        if metadata is None:
            assets = {asset['name']: asset for asset in release['assets'] if asset['state'] == 'uploaded'}
            asset = assets.get('release.json') or assets.get('package-info.txt')
            if asset is None:
                if release['draft']:
                    continue
                raise ValueError(f"Cannot determine historical Android build number: {release['tag_name']}")
            payload = gh('api', f"repos/{repository}/releases/assets/{asset['id']}",
                         '-H', 'Accept: application/octet-stream')
            if asset['name'] == 'release.json':
                metadata = json.loads(payload)
            else:
                match = re.search(r"versionCode='([1-9]\d*)'", payload)
                if not match:
                    raise ValueError('Historical package metadata is invalid')
                metadata = {'build_number': int(match[1])}
        release['metadata'] = metadata
    return releases


def next_core(core, commits):
    major, minor, patch = core
    breaking = re.search(r'(?m)^[\w-]+(?:\([^\n)]+\))?!:|^BREAKING[ -]CHANGE:', commits)
    if breaking:
        return (major + 1, 0, 0) if major else (0, minor + 1, 0)
    if re.search(r'(?m)^feat(?:\([^\n)]+\))?:', commits):
        return major, minor + 1, 0
    return major, minor, patch + 1


def plan_release(source, branch, source_sha, releases, tags=(), commits=''):
    if branch not in {'beta', 'main'}:
        raise ValueError('Android releases are only allowed from beta or main')
    if not re.fullmatch(r'[a-f0-9]{40}', source_sha):
        raise ValueError('Source must be an exact commit SHA')
    matching = [release for release in releases
                if (release.get('metadata') or {}).get('source_sha') == source_sha
                and (release.get('metadata') or {}).get('branch') == branch]
    if len(matching) > 1:
        raise ValueError('Multiple releases exist for the same source and channel')
    if matching and not matching[0]['draft']:
        return {'skip': 'true', 'tag': matching[0]['tag_name']}
    builds = [source['build_number']]
    for release in releases:
        metadata = release.get('metadata')
        if metadata is not None:
            build = metadata.get('build_number')
            if type(build) is not int or not 0 < build <= 2100000000:
                raise ValueError('Historical Android build number is invalid')
            builds.append(build)
    if matching:
        existing = matching[0]['metadata']
        if existing['build_number'] < max(builds):
            raise ValueError('Draft was superseded; do not publish an older Android build')
        version, build = existing['version'], existing['build_number']
    else:
        parsed = [value for tag in [*tags, *(release['tag_name'] for release in releases)]
                  if (value := version_parts(tag))]
        source_parts = version_parts(source['version'])
        core = max([source_parts[0], *(value[0] for value in parsed)])
        stable = [value[0] for value in parsed if value[1] is None]
        if stable:
            core = max(core, next_core(max(stable), commits))
        if branch == 'beta':
            candidates = [value[2] for value in parsed if value[0] == core and value[1] == 'beta']
            if source_parts[0] == core and source_parts[1] == 'beta':
                candidates.append(source_parts[2])
            if any(value[0] == core and value[1] == 'rc' for value in parsed):
                core = (core[0], core[1], core[2] + 1)
                candidates = []
            version = '.'.join(map(str, core)) + f'-beta.{max(candidates, default=0) + 1}'
        else:
            version = '.'.join(map(str, core))
        build = max(builds) + 1
    if build > 2100000000:
        raise ValueError('Android versionCode exceeds 2100000000')
    return {
        'skip': 'false', 'version': version, 'build_number': build,
        'channel': 'beta' if branch == 'beta' else 'stable',
        'tag': f'v{version}', 'source_sha': source_sha, 'branch': branch,
        'filename': f'night-sleep-{version}-android.apk',
        'artifact_name': f'night-sleep-{version}-build.{build}-android',
    }


def change_summary(previous_sha, source_sha):
    """List commit subjects added since the previous release on the same channel."""
    # 提交信息是中文：Windows 上用 text=True 会按 GBK 解码而崩掉。
    base = subprocess.check_output(
        ['git', 'merge-base', previous_sha, source_sha], encoding='utf-8').strip()
    log = subprocess.check_output(
        ['git', 'log', '--no-merges', '--format=%s', f'{base}..{source_sha}'], encoding='utf-8')
    subjects = (line.strip() for line in log.splitlines() if line.strip())
    return list(dict.fromkeys(
        subject for subject in subjects if not CHANGE_NOISE.match(subject)))[:CHANGE_LIMIT]


def previous_release(releases, identity):
    """Return the newest comparable release of the same channel before this build.

    Legacy releases built before release markers carry no source commit, so they
    cannot be diffed against; skip back to the newest one that can.
    """
    candidates = [release for release in releases
                  if not release['draft']
                  and (release.get('metadata') or {}).get('branch') == identity['branch']
                  and re.fullmatch(r'[a-f0-9]{40}', (release.get('metadata') or {}).get('source_sha') or '')
                  and (release.get('metadata') or {}).get('build_number', 0) < identity['build_number']]
    return max(candidates, key=lambda item: item['metadata']['build_number'], default=None)


def release_notes(identity, releases):
    sections = [f"夜深 Android {identity['version']}（构建 {identity['build_number']}）"]
    previous = previous_release(releases, identity)
    if previous is not None:
        changes = change_summary(previous['metadata']['source_sha'], identity['source_sha'])
        if changes:
            lines = [f"## 本次改动（对比 {previous['tag_name']}）", '']
            lines.extend(f'- {change}' for change in changes)
            sections.append('\n'.join(lines))
    sections.append(f"Source: {identity['source_sha']}")
    return ('\n\n'.join(sections) + '\n\n<!-- night-sleep-release '
            + json.dumps(identity, separators=(',', ':')) + ' -->\n')


def publish(repository, directory):
    folder = Path(directory)
    metadata = json.loads((folder / 'release.json').read_text())
    identity = {key: metadata[key] for key in ('version', 'build_number', 'source_sha', 'branch')}
    parsed = version_parts(identity['version'])
    if (metadata['tag'] != f"v{metadata['version']}" or parsed is None
            or identity['branch'] not in {'beta', 'main'}
            or (identity['branch'] == 'beta') != bool(parsed[1])
            or type(identity['build_number']) is not int
            or not 0 < identity['build_number'] <= 2100000000
            or not re.fullmatch(r'[a-f0-9]{40}', identity['source_sha'])):
        raise ValueError('Artifact release identity is invalid')
    releases = load_releases(repository)
    release = next((item for item in releases if item['tag_name'] == metadata['tag']), None)
    if release is not None:
        marker = release_marker(release)
        if marker != identity:
            raise ValueError('Existing release belongs to a different build; never overwrite it')
        if not release['draft']:
            print(f"Already published {metadata['tag']}")
            return
    notes = folder / 'release-notes.md'
    notes.write_text(release_notes(identity, releases))
    if release is None:
        gh('release', 'create', metadata['tag'], '--repo', repository,
           '--target', identity['source_sha'], '--draft', '--title',
           f"夜深 Android {metadata['version']}", '--notes-file', str(notes))
    assets = [str(folder / metadata['filename']), str(folder / 'release.json')]
    gh('release', 'upload', metadata['tag'], '--repo', repository, '--clobber', *assets)
    beta = identity['branch'] == 'beta'
    gh('release', 'edit', metadata['tag'], '--repo', repository, '--draft=false',
       f'--prerelease={str(beta).lower()}', f'--latest={str(not beta).lower()}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    plan = commands.add_parser('plan')
    plan.add_argument('--repository', required=True)
    plan.add_argument('--branch', required=True)
    plan.add_argument('--source-sha', required=True)
    plan.add_argument('--github-output', required=True)
    apply = commands.add_parser('apply')
    apply.add_argument('--version', required=True)
    apply.add_argument('--build-number', type=int, required=True)
    release = commands.add_parser('publish')
    release.add_argument('--repository', required=True)
    release.add_argument('--directory', default='artifacts/android')
    args = parser.parse_args()
    if args.command == 'apply':
        write_version('pubspec.yaml', args.version, args.build_number)
    elif args.command == 'publish':
        publish(args.repository, args.directory)
    else:
        releases = load_releases(args.repository)
        stable = [item for item in releases if not item['draft'] and version_parts(item['tag_name'])[1] is None]
        commits = ''
        if stable:
            latest = max(stable, key=lambda item: version_parts(item['tag_name']))
            subprocess.run(['git', 'merge-base', '--is-ancestor', latest['tag_name'], args.source_sha], check=True)
            commits = subprocess.check_output(
                ['git', 'log', '--format=%B', f"{latest['tag_name']}..{args.source_sha}"], encoding='utf-8')
        if args.branch == 'main':
            for item in releases:
                identity = item.get('metadata') or {}
                if not item['draft'] and identity.get('branch') == 'beta':
                    subprocess.run(['git', 'merge-base', '--is-ancestor', identity['source_sha'], args.source_sha], check=True)
        tags = subprocess.check_output(['git', 'tag', '--list', 'v*'], text=True).splitlines()
        metadata = plan_release(read_version('pubspec.yaml'), args.branch, args.source_sha, releases, tags, commits)
        with Path(args.github_output).open('a') as stream:
            for key, value in metadata.items():
                stream.write(f'{key}={value}\n')
        print(json.dumps(metadata))


if __name__ == '__main__':
    main()
