# Release branches

- Work on feature branches or `beta`. Merging or pushing application changes to `beta` automatically publishes an Android Beta after checks pass.
- Merge or push to `main` only when the user explicitly requests a formal release. Application changes on `main` automatically publish a stable Android version. Do not promote Beta work to `main` as routine cleanup.
- Do not manually create release tags or increment Beta sequences/build numbers. The Android workflow derives versions from release history and Conventional Commits, verifies the APK, then creates the tag and Release for the exact source commit.
- Use `fix:` for patches, `feat:` for minor releases, and `!` / `BREAKING CHANGE:` for breaking changes. Before 1.0, breaking changes increment the minor version. `pubspec.yaml` supplies the minimum target version for an intentional version jump.
- After a formal release, synchronize `main` back into `beta` before continuing development.
- The website deploys independently from both release branches. Its primary Android download is always the latest stable version; Beta is a separate optional entry and must never replace a missing stable download.

# Validation

- Release automation: `python3 -m unittest discover -s tool -p 'test_*release.py'` and `python3 -m unittest discover -s tool -p 'test_*signing.py'`.
- Website: run `npm run check` and `npm run build` in `website/`.
- Flutter changes: run `dart analyze` and relevant Flutter tests.
