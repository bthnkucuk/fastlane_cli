---
name: fastlane-play-internal
description: End-to-end Android Play Console internal-track release flow via fastlane_cli — service account, version handling, and the canonical action ids. Triggers on: play internal, play console internal, android internal, android beta, internal testing, android_internal_testing, android_internal_bump_deploy, AAB upload (non-production).
---

# fastlane_cli — Android Play internal flow

Use this skill when the user wants to ship an Android AAB to the Play Console
internal track (or `alpha` / `beta`, configurable). For production releases
the relevant action is `android_production` (flagged
`requires_confirmation: true`) — covered briefly at the bottom.

## Prerequisites

### 1. Google Play service-account key

A JSON key for a service account that has the **Release manager** role
(minimum) on the Play Console project. Path goes in env:

```sh
export GOOGLE_PLAY_JSON_KEY_PATH="/abs/path/to/play-service-account.json"
```

This is read by `FastlaneCliConfig.absolute_json_key` and passed to every
`google_play_*` call in the Android lanes.

### 2. Package name

Either declared in `app.android.package_name` of `profile.yaml`, or via
env:

```sh
export ANDROID_PACKAGE_NAME="com.example.app"
# or, if iOS + Android share the id:
export FASTLANE_APP_IDENTIFIER="com.example.app"
```

### 3. Flutter + Android signing

A working `flutter build appbundle --release` must already produce a signed
AAB at `build/app/outputs/bundle/release/app-release.aab` (or
`app-<flavor>-release.aab` for flavored projects). fastlane_cli doesn't
manage `key.properties`.

### 4. Crashlytics symbol upload — not wired

**This repo does not invoke `uploadCrashlyticsMappingFile<Variant>` or
`uploadCrashlyticsSymbolFile<Variant>` from any Android lane.** R8 mapping
files may still reach Firebase as a side-effect of the Crashlytics Gradle
plugin (`mappingFileUploadEnabled = true` default) during
`flutter build appbundle --release` — that path is outside fastlane_cli.
Native (NDK) crash symbolication has no automatic path.

If the user explicitly asks for Android Crashlytics symbol upload via
fastlane_cli, do **not** invent an action id — hand off to
[`fastlane-crashlytics-symbols`](../fastlane-crashlytics-symbols/SKILL.md)
which documents the gap and the lane-extension shape.

## Choose the action

Discover the live set with `fastlane_cli list --json --profile <path>` first,
then pick from these base options (all in the `android` category):

| Action id                            | Lane (`android`)          | Bumps version? | Confirms? | Use when                                                                            |
| ------------------------------------ | ------------------------- | -------------- | --------- | ----------------------------------------------------------------------------------- |
| `android_internal_bump_deploy`       | `internal_test` (`platform: android`)                | yes            | yes       | Standard "ship a new internal build" — bumps patch + versionCode, uploads to Play.  |
| `android_internal_no_bump_deploy`    | `internal_test` (`platform: android`, `skip_bump: "true"`) | no             | no        | Re-upload current pubspec version (rare; usually only after a previous upload failed before Play processing). |
| `android_internal_testing`           | `internal_testing` (android)                         | no             | no        | Direct call to the Play `internal` track upload lane. Assumes an AAB is already built and resolvable. |
| `internal_test` (general)            | `internal_test` (top-level)                          | yes            | yes       | Bumps + ships for **both** Android and iOS in one shot.                             |
| `android_version_status`             | `version_status` (android)                           | no             | no        | Read-only sanity check before / after a deploy.                                     |
| `android_production`                 | `production` (android)                               | no             | yes       | Production track. Separate flow — confirm with the user before invoking.            |
| `android_google_play_help`           | `google_play_help` (android)                         | n/a            | no        | Surfaces remediation tips for common Play Console error responses.                  |

The `internal_test` lane chain (used by `*_internal_*_deploy`) runs roughly:

1. Resolve pubspec / package id / flavor.
2. Call `google_play_track_version_codes` for the configured track (default
   `internal`) and the `fallback_track` (default `production`).
3. Compute `next_code = max(remote_codes, local) + 1`. The summary box
   spells the rule out — quote it back to the user.
4. (When `skip_bump != "true"`) write `version: <name>+<next_code>` into
   `pubspec.yaml`.
5. Build the AAB (`flutter build appbundle --release`, flavor-aware).
6. `upload_to_play_store` against the chosen track.
7. Print the `Android · Internal Testing yüklendi` summary box.

## Invocation

```sh
fastlane_cli run android_internal_bump_deploy --profile <path>
```

"Just upload an already-built AAB" — make sure the AAB exists at the
resolved path first, then:

```sh
fastlane_cli run android_internal_testing --profile <path>
```

Dry-run to preview the command:

```sh
fastlane_cli run android_internal_bump_deploy --profile <path> --dry-run
```

## Track selection

The base `android_internal_testing` action targets the `internal` track. To
override (e.g. `alpha` or `beta`), the per-app `profile.yaml` should
declare a replacement entry by `id` with `command.options.track: alpha` (or
`beta`). The Play Console treats `internal`, `alpha`, `beta`, `production`
as distinct tracks with separate release ladders.

## After the upload

- The build appears under the chosen track within seconds (vs minutes on
  iOS).
- Release status defaults to `completed`; override via profile if you want
  `draft` or `inProgress` rollouts.
- The summary box prints the package name, flavor, track, release status,
  and AAB path. Quote that back to the user.

## Troubleshooting

- **"The caller does not have permission"** — service account lacks Release
  manager role, or wasn't added in Play Console → Setup → API access.
- **"versionCode N has already been used"** — Play rejected the upload
  because the local `+N` collides with an existing build. Re-run a bump
  action; the lane recomputes `max + 1`.
- **AAB not found** — confirm `flutter build appbundle --release` succeeds
  independently; verify flavor matches `FASTLANE_FLAVOR`.
- General Play API errors → run `android_google_play_help` for the
  built-in remediation table.

For deeper credential/env diagnostics, hand off to the `fastlane-doctor`
skill.

## Do not

- Run `android_production` when the user only asked for internal — that
  pushes to the live store track.
- Hand-edit `pubspec.yaml` and then run `android_internal_bump_deploy` —
  the bump overwrites the manual edit.
- Commit `play-service-account.json` to git.
