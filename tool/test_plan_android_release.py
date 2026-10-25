import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from android_release import read_version, write_version
from plan_android_release import (change_summary, load_releases, next_core, plan_release,
                                  previous_release, publish, release_marker, release_notes)


SOURCE_SHA = 'a' * 40
OLDER_SHA = 'b' * 40


def history(version='0.49.0-beta.2', build=3, branch='beta', source_sha=OLDER_SHA, draft=False):
    metadata = {'version': version, 'build_number': build, 'branch': branch, 'source_sha': source_sha}
    return {
        'tag_name': f'v{version}', 'draft': draft, 'metadata': metadata, 'assets': [],
        'body': '<!-- night-sleep-release ' + json.dumps(metadata) + ' -->',
    }


class PlanAndroidReleaseTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.pubspec = Path(self.directory.name) / 'pubspec.yaml'
        self.pubspec.write_text('name: night_sleep\nversion: 0.49.0-beta.2+3\n')
        self.source = read_version(self.pubspec)

    def plan(self, branch='beta', releases=None, **options):
        return plan_release(self.source, branch, SOURCE_SHA,
                            [history()] if releases is None else releases, **options)

    def test_beta_increments_both_version_and_global_build(self):
        result = self.plan()
        self.assertEqual(result['version'], '0.49.0-beta.3')
        self.assertEqual(result['build_number'], 4)
        self.assertEqual(result['channel'], 'beta')
        self.assertEqual(result['source_sha'], SOURCE_SHA)

    def test_main_promotes_beta_to_stable_and_uses_next_build(self):
        result = self.plan('main', [history('0.49.0-beta.7', 12)])
        self.assertEqual(result['version'], '0.49.0')
        self.assertEqual(result['build_number'], 13)
        self.assertEqual(result['channel'], 'stable')

    def test_patch_minor_and_breaking_conventional_commits(self):
        for commits, expected in [
            ('fix(player): correct timing', (0, 49, 1)),
            ('feat(settings): add updates', (0, 50, 0)),
            ('feat(settings)!: replace storage', (0, 50, 0)),
            ('refactor(storage): migrate\n\nBREAKING CHANGE: old format removed', (0, 50, 0)),
        ]:
            with self.subTest(commits=commits):
                self.assertEqual(next_core((0, 49, 0), commits), expected)
        self.assertEqual(next_core((1, 2, 3), 'fix!: remove API'), (2, 0, 0))

    def test_beta_after_stable_uses_next_semantic_version(self):
        releases = [history('0.49.0', 7, 'main')]
        self.assertEqual(self.plan(releases=releases)['version'], '0.49.1-beta.1')
        self.assertEqual(self.plan(releases=releases, commits='feat: new feature')['version'], '0.50.0-beta.1')

    def test_stable_includes_higher_beta_version(self):
        releases = [history('0.49.0', 7, 'main'), history('0.50.0-beta.1', 8)]
        self.assertEqual(self.plan('main', releases)['version'], '0.50.0')

    def test_branch_channels_share_monotonic_builds_and_reserve_drafts(self):
        releases = [history('0.49.0', 8, 'main'), history('0.50.0-beta.1', 9, draft=True)]
        result = self.plan(releases=releases)
        self.assertEqual(result['build_number'], 10)
        self.assertEqual(result['version'], '0.50.0-beta.2')

    def test_orphan_tags_are_not_reused(self):
        result = self.plan(tags=['v0.49.0-beta.3', 'v0.49.0-beta.10'])
        self.assertEqual(result['version'], '0.49.0-beta.11')

    def test_beta_never_downgrades_an_rc(self):
        self.assertEqual(self.plan(tags=['v0.49.0-rc.1'])['version'], '0.49.1-beta.1')

    def test_retry_published_source_skips_and_draft_reuses_identity(self):
        release = history(source_sha=SOURCE_SHA)
        self.assertEqual(self.plan(releases=[release])['skip'], 'true')
        release['draft'] = True
        result = self.plan(releases=[release])
        self.assertEqual(result['version'], '0.49.0-beta.2')
        self.assertEqual(result['build_number'], 3)
        self.assertEqual(result['skip'], 'false')

    def test_same_commit_can_be_promoted_on_main(self):
        result = self.plan('main', [history(source_sha=SOURCE_SHA)])
        self.assertEqual(result['version'], '0.49.0')
        self.assertEqual(result['skip'], 'false')

    def test_superseded_draft_cannot_publish_an_older_build(self):
        releases = [history(source_sha=SOURCE_SHA, draft=True), history('0.49.0-beta.3', 4)]
        with self.assertRaisesRegex(ValueError, 'superseded'):
            self.plan(releases=releases)

    def test_unknown_branch_invalid_sha_or_build_fails(self):
        with self.assertRaises(ValueError):
            self.plan('feature')
        with self.assertRaises(ValueError):
            plan_release(self.source, 'beta', 'main', [])
        for build in [0, '4', 2100000001]:
            with self.subTest(build=build), self.assertRaises(ValueError):
                self.plan(releases=[history(build=build)])
        with self.assertRaises(ValueError):
            self.plan(releases=[history(build=2100000000)])

    def test_apply_changes_only_version_and_rejects_invalid_values(self):
        write_version(self.pubspec, '0.49.0-beta.3', 4)
        expected = 'name: night_sleep\nversion: 0.49.0-beta.3+4\n'
        self.assertEqual(self.pubspec.read_text(), expected)
        with self.assertRaises(ValueError):
            write_version(self.pubspec, 'bad', 5)
        self.assertEqual(self.pubspec.read_text(), expected)

    def test_marker_must_agree_with_release_identity(self):
        release = history()
        self.assertEqual(release_marker(release), release['metadata'])
        release['tag_name'] = 'v0.49.0-beta.3'
        with self.assertRaises(ValueError):
            release_marker(release)
        with self.assertRaisesRegex(ValueError, 'branch'):
            release_marker(history(branch='main'))

    @patch('plan_android_release.gh')
    def test_loads_paginated_history_and_legacy_metadata(self, command):
        modern = history()
        legacy = {'tag_name': 'v0.49.0-beta.1', 'draft': False, 'assets': [
            {'name': 'release.json', 'state': 'uploaded', 'id': 42}], 'body': ''}
        preview = {'tag_name': 'v0.49.0-preview.1', 'draft': False, 'assets': [
            {'name': 'package-info.txt', 'state': 'uploaded', 'id': 43}], 'body': ''}
        command.side_effect = [json.dumps([[modern], [legacy, preview]]),
                               json.dumps({'build_number': 2}), "package: versionCode='1'"]
        releases = load_releases('owner/repo')
        self.assertEqual([item['metadata']['build_number'] for item in releases], [3, 2, 1])
        self.assertIn('--paginate', command.call_args_list[0].args)

    @patch('plan_android_release.gh')
    def test_missing_historical_build_fails_closed(self, command):
        release = {'tag_name': 'v0.49.0', 'draft': False, 'assets': [], 'body': ''}
        command.return_value = json.dumps([[release]])
        with self.assertRaisesRegex(ValueError, 'historical'):
            load_releases('owner/repo')

    @patch('plan_android_release.subprocess.check_output')
    def test_change_summary_diffs_from_merge_base_and_skips_noise(self, run):
        run.side_effect = [
            'c' * 40 + '\n',
            'feat: 新增睡眠日历\nfix: 修复冷启动白屏\nchore(release): 发布\n'
            'fix: 修复冷启动白屏\ndocs: 更新说明\ntest: 补用例\n',
        ]
        self.assertEqual(change_summary(OLDER_SHA, SOURCE_SHA),
                         ['feat: 新增睡眠日历', 'fix: 修复冷启动白屏'])
        self.assertEqual(run.call_args_list[0].args[0][:2], ['git', 'merge-base'])
        self.assertEqual(run.call_args_list[1].args[0][-1], f"{'c' * 40}..{SOURCE_SHA}")

    def test_previous_release_is_newest_published_of_the_same_channel(self):
        releases = [history('0.49.0', 4, 'main'), history('0.49.0-beta.4', 6, draft=True),
                    history('0.49.0-beta.2', 2), history('0.49.0-beta.3', 3)]
        identity = {'branch': 'beta', 'build_number': 5}
        self.assertEqual(previous_release(releases, identity)['tag_name'], 'v0.49.0-beta.3')
        self.assertIsNone(previous_release(releases, {'branch': 'beta', 'build_number': 2}))

    def test_legacy_release_without_source_commit_is_not_a_diff_base(self):
        legacy = history('0.49.0-beta.4', 4)
        legacy['metadata'] = {'build_number': 4, 'branch': 'beta'}
        releases = [history('0.49.0-beta.2', 2), legacy]
        self.assertEqual(previous_release(releases, {'branch': 'beta', 'build_number': 5})['tag_name'],
                         'v0.49.0-beta.2')

    @patch('plan_android_release.change_summary', return_value=['feat: 新增睡眠日历'])
    def test_release_notes_list_changes_since_the_previous_release(self, changes):
        identity = {'version': '0.49.0-beta.3', 'build_number': 4,
                    'branch': 'beta', 'source_sha': SOURCE_SHA}
        notes = release_notes(identity, [history('0.49.0', 1, 'main'),
                                         history('0.49.0-beta.2', 2)])
        self.assertIn('夜深 Android 0.49.0-beta.3（构建 4）', notes)
        self.assertIn('## 本次改动（对比 v0.49.0-beta.2）', notes)
        self.assertIn('- feat: 新增睡眠日历', notes)
        self.assertIn(f'Source: {SOURCE_SHA}', notes)
        self.assertIn('<!-- night-sleep-release ', notes)
        changes.assert_called_once_with(OLDER_SHA, SOURCE_SHA)

    @patch('plan_android_release.change_summary')
    def test_first_release_has_no_change_section(self, changes):
        identity = {'version': '0.49.0', 'build_number': 1,
                    'branch': 'main', 'source_sha': SOURCE_SHA}
        notes = release_notes(identity, [])
        self.assertIn('夜深 Android 0.49.0（构建 1）', notes)
        self.assertNotIn('本次改动', notes)
        self.assertIn(f'Source: {SOURCE_SHA}', notes)
        changes.assert_not_called()

    def artifacts(self, branch='beta'):
        metadata = self.plan(branch)
        folder = Path(self.directory.name) / 'artifacts'
        folder.mkdir()
        (folder / 'release.json').write_text(json.dumps(metadata))
        (folder / metadata['filename']).write_bytes(b'APK')
        return folder, metadata

    @patch('plan_android_release.gh')
    @patch('plan_android_release.load_releases', return_value=[])
    def test_publish_creates_draft_at_exact_sha_then_uploads_and_exposes(self, releases, command):
        folder, metadata = self.artifacts()
        for filename in ('package-info.txt', 'signature.txt', 'SHA256SUMS.txt', 'debug.log'):
            (folder / filename).write_text('Build verification output\n')
        publish('owner/repo', folder)
        calls = [call.args for call in command.call_args_list]
        self.assertIn(SOURCE_SHA, calls[0])
        self.assertIn('--draft', calls[0])
        self.assertEqual(calls[1], (
            'release', 'upload', metadata['tag'], '--repo', 'owner/repo', '--clobber',
            str(folder / metadata['filename']), str(folder / 'release.json'),
        ))
        self.assertEqual(calls[2][:2], ('release', 'edit'))
        self.assertIn('--prerelease=true', calls[2])
        self.assertIn('--latest=false', calls[2])
        self.assertNotIn(str(folder / 'release-notes.md'), calls[1])

    @patch('plan_android_release.change_summary', return_value=['fix: 修复冷启动白屏'])
    @patch('plan_android_release.gh')
    @patch('plan_android_release.load_releases')
    def test_publish_puts_changes_since_last_build_into_notes(self, releases, command, changes):
        folder, metadata = self.artifacts()
        releases.return_value = [history('0.49.0-beta.2', metadata['build_number'] - 1)]
        publish('owner/repo', folder)
        notes = (folder / 'release-notes.md').read_text()
        self.assertIn('## 本次改动（对比 v0.49.0-beta.2）', notes)
        self.assertIn('- fix: 修复冷启动白屏', notes)
        self.assertEqual(changes.call_args.args[0], OLDER_SHA)

    @patch('plan_android_release.gh')
    @patch('plan_android_release.load_releases', return_value=[])
    def test_stable_is_published_as_latest(self, releases, command):
        folder, metadata = self.artifacts('main')
        publish('owner/repo', folder)
        self.assertIn('--prerelease=false', command.call_args.args)
        self.assertIn('--latest=true', command.call_args.args)

    @patch('plan_android_release.gh')
    def test_publish_rejects_mismatched_branch_and_version(self, command):
        folder, metadata = self.artifacts()
        metadata['branch'] = 'main'
        (folder / 'release.json').write_text(json.dumps(metadata))
        with self.assertRaisesRegex(ValueError, 'identity'):
            publish('owner/repo', folder)
        command.assert_not_called()

    @patch('plan_android_release.gh')
    @patch('plan_android_release.load_releases')
    def test_published_release_is_immutable_and_draft_retry_is_safe(self, releases, command):
        folder, metadata = self.artifacts()
        release = history(metadata['version'], metadata['build_number'], source_sha=SOURCE_SHA)
        releases.return_value = [release]
        publish('owner/repo', folder)
        command.assert_not_called()
        release['draft'] = True
        publish('owner/repo', folder)
        self.assertEqual(command.call_args_list[0].args[:2], ('release', 'upload'))
        command.reset_mock()
        releases.return_value = [history(metadata['version'], metadata['build_number'])]
        with self.assertRaisesRegex(ValueError, 'never overwrite'):
            publish('owner/repo', folder)
        command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
