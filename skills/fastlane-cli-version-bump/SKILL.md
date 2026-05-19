---
name: fastlane-cli-version-bump
description: Bump fastlane_cli's own pubspec.yaml version + formula version when shipping a PR that warrants it. Triggers on: bump fastlane_cli, release fastlane_cli, cut fastlane_cli, fastlane_cli version, fastlane_cli release, ship fastlane_cli.
---

# fastlane_cli — own-repo version bump

Use this skill when shipping a PR against the `fastlane_cli` repo itself and
the change warrants a version bump. This is **not** the consumer-app bump
skill (`fastlane-version-bump`), which mutates a Flutter app's
`pubspec.yaml` via lanes; this one only touches *this repo's* own
`pubspec.yaml` + the homebrew formula draft.

## When to bump (per PR, before opening it)

Decide from the conventional-commits type of the PR's primary change:

| Change type                                                                                                                                                            | Bump                          | Example                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- | ------------------------------------ |
| `feat:` — new public API, new subcommand, new skill, user-visible new behaviour                                                                                        | **minor** (`0.1.0` → `0.2.0`) | "add `fastlane_cli skills list`"     |
| `fix:` / `refactor:` / behaviour-preserving change / dep bump                                                                                                          | **patch** (`0.1.0` → `0.1.1`) | "fix process supervision on SIGINT"  |
| Breaking change (renamed CLI flag, removed subcommand, removed public Dart export, changed exit-code contract). Marked with `!` suffix (`feat!:`) or `BREAKING CHANGE:` | **major** (`0.1.0` → `1.0.0`) | "rename `--profile` to `--config`"   |
| `chore:` / `docs:` / `ci:` / `test:` alone                                                                                                                             | **no bump**                   | "update README", "bump CI action"    |

Multiple `chore:` / `docs:` / `ci:` PRs accumulate into the **next real**
bump from a `feat` / `fix` change — they do not earn their own version.

If a single PR spans multiple types, the highest-precedence change wins
(major > minor > patch > none).

## Where to update (atomic, in one commit)

Touch exactly these three files in the same commit as the change being shipped:

1. `pubspec.yaml` — the `version:` line. Format `X.Y.Z` (no `+N` build
   suffix; this CLI is not deployed to app stores).
2. `dist/homebrew/Formula/fastlane_cli.rb` — the `version "X.Y.Z"` line.
   The `url` lines that contain `v0.1.0` are rewritten by release CI
   (Track D2) on tag push; the skill should not touch them manually.
3. `lib/src/version.dart` — the `fastlaneCliVersion` constant. This is
   what `fastlane_cli --version` prints, so it MUST move in lockstep
   with `pubspec.yaml` and the homebrew formula. Re-exported from
   `lib/fastlane_cli.dart`.

Do **not** modify:

- `lib/src/localization/i18n/strings.g.dart` or any other generated file.
- The `url "...v0.1.0/..."` lines in the formula — those are
  release-CI-owned.
- `CHANGELOG.md` if one is added later — that is a separate concern.

## How to verify (post-bump)

Run from the repo root:

```sh
fvm dart pub get
fvm dart test
fvm dart analyze
git diff pubspec.yaml dist/homebrew/Formula/fastlane_cli.rb lib/src/version.dart
fvm dart run bin/fastlane_cli.dart --version   # → "fastlane_cli X.Y.Z"
```

The diff should show **only the three version lines** changed. Tests must
remain green; analyze must remain clean. The `--version` output must
match the new `X.Y.Z` exactly.

## When the supervisor cuts a release

After the PR merges:

1. The tag name is `vX.Y.Z` and matches `pubspec.yaml` `version:` exactly.
2. The supervisor runs:

   ```sh
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. The release workflow (`.github/workflows/release.yml`) builds the
   per-platform tarballs and publishes the GitHub release.
4. Track D2 (in flight) will then auto-rewrite the tap formula's `url` +
   `sha256` lines in `bthnkucuk/homebrew-fastlane_cli`. Until that
   lands, the formula `version` field in this repo is manually kept in
   lockstep with `pubspec.yaml` (which is exactly what this skill does).

The sub-agent doing the PR does **not** create the tag — only the
supervisor does, after CI green + merge.

## Worked example

Suppose a PR adds the `fastlane_cli skills list` subcommand. Recent commits:

```
* feat(skills): add `skills list` subcommand
* test(skills): cover skills list output ordering
* docs(readme): document skills list
```

Decision: highest-precedence change is `feat:` → **minor** bump.

Current `pubspec.yaml`:

```yaml
version: 0.1.0
```

Current `dist/homebrew/Formula/fastlane_cli.rb`:

```ruby
  version "0.1.0"
```

Diff after applying the bump (committed with the feature):

```diff
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@
-version: 0.1.0
+version: 0.2.0

--- a/dist/homebrew/Formula/fastlane_cli.rb
+++ b/dist/homebrew/Formula/fastlane_cli.rb
@@
-  version "0.1.0"
+  version "0.2.0"

--- a/lib/src/version.dart
+++ b/lib/src/version.dart
@@
-const String fastlaneCliVersion = '0.1.0';
+const String fastlaneCliVersion = '0.2.0';
```

Commit message style (lockstepped with the feature commit, or a follow-up
`chore(version): bump to 0.2.0` if the feature was already committed):

```
chore(version): bump to 0.2.0 for `skills list` subcommand
```

After merge, the supervisor tags `v0.2.0` and pushes it.

## Do not

- Bump for a pure `chore:` / `docs:` / `ci:` / `test:` PR.
- Skip the formula update — all three files (pubspec, formula, and
  `lib/src/version.dart`) must move together so the released tarball
  metadata, the binary's `--version` output, and the homebrew formula
  are internally consistent.
- Edit the formula's `url` lines or `sha256` placeholders.
- Tag the release from a sub-agent PR; only the supervisor tags `main`
  after merge.
- Hand-edit a generated `strings.g.dart` even if a localization key happens
  to mention a version number (it does not — this is a guardrail).
