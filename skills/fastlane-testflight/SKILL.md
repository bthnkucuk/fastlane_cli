---
name: fastlane-testflight
description: End-to-end iOS TestFlight release flow via fastlane_cli — credential prerequisites, version handling, and the canonical action ids. Triggers on: testflight, test flight, iOS internal, iOS beta, beta build, App Store Connect upload (non-production), ios_test_flight, ios_internal_bump_deploy.
---

# fastlane_cli — iOS TestFlight flow

Use this skill when the user wants to ship an iOS build to TestFlight (any
internal / external tester group). For App Store production submissions use
the action ids prefixed `ios_app_store` / `ios_deploy_appstore` — they live
under the same category but are flagged `requires_confirmation: true`.

To submit a build **already on TestFlight** to App Store review without
re-uploading a binary, use `ios_promote_to_app_store` — see
[`fastlane-appstore-promote`](../fastlane-appstore-promote/SKILL.md).

## Prerequisites

### 1. App Store Connect credentials

Set one of (priority order — see [CLAUDE.md](../../CLAUDE.md) §5.3 and the
header of [`fastlane/ios/Fastfile`](../../fastlane/ios/Fastfile)):

```sh
# Preferred: single JSON key file.
export APP_STORE_CONNECT_API_KEY_JSON_PATH="/abs/path/to/api_key.json"

# Or: the .p8 + ids triple.
export APP_STORE_CONNECT_API_KEY_ID="ABC123"
export APP_STORE_CONNECT_API_KEY_ISSUER_ID="xxxx-xxxx-xxxx-xxxx"
export APP_STORE_CONNECT_API_KEY_FILEPATH="/abs/path/AuthKey_ABC123.p8"
```

A `FASTLANE_SESSION` cookie also works but expires; API key is preferred.

### 2. Bundle identifier

Either declared in `app.ios.app_identifier` of `cli_profile.yaml`, or via
env:

```sh
export IOS_APP_IDENTIFIER="com.example.app"
# or, if iOS + Android share an id:
export FASTLANE_APP_IDENTIFIER="com.example.app"
```

### 3. Xcode + signing

Xcode + a valid signing setup (match / manual) must already work locally —
fastlane_cli doesn't manage signing. Confirm `xcodebuild -version` returns a
modern version.

### 4. Crashlytics dSYM upload (optional)

The `test_flight` lane has an opt-in `upload_symbols` flag (default `false`)
that pushes dSYMs to Firebase Crashlytics right after the TestFlight upload
succeeds. When the user asks for symbolicated production crashes, hand off
to [`fastlane-crashlytics-symbols`](../fastlane-crashlytics-symbols/SKILL.md)
for the env vars, profile-override pattern, and the standalone
`upload_dsyms` lane.

## Choose the action

Discover the live set first with `fastlane_cli list --json --profile <path>`,
then pick from these base options (all in the `ios` category):

| Action id                       | Lane (`ios`)          | Bumps version? | Confirms? | Use when                                                                |
| ------------------------------- | --------------------- | -------------- | --------- | ----------------------------------------------------------------------- |
| `ios_internal_bump_deploy`      | `internal_test` (`platform: ios`)                | yes            | yes       | Standard "ship a new TestFlight build" — bumps patch + build, uploads.  |
| `ios_internal_no_bump_deploy`   | `internal_test` (`platform: ios`, `skip_bump: "true"`) | no             | no        | Re-upload the current pubspec version (rare; usually only when a previous upload failed *after* build but before processing). |
| `ios_test_flight`               | `test_flight`         | no             | no        | Direct call to the TestFlight upload lane. Assumes an IPA already exists at the resolved path.                                |
| `ios_deploy_testflight`         | `deploy_testflight`   | no             | no        | Backward-compat alias of `test_flight`. Prefer `ios_test_flight`.       |
| `internal_test` (general)       | `internal_test` (top-level)                      | yes            | yes       | Bumps + ships for **both** iOS and Android in one shot.                 |

The `internal_test` lane chain (used by all `*_internal_*_deploy` actions)
runs roughly:

1. Resolve pubspec / package id / flavor.
2. Read remote highest build number (App Store Connect via Spaceship).
3. Compute next `build_number = max(local, remote) + 1`. The summary box
   emitted at the end of the lane spells the rule out — quote it back to
   the user.
4. (When `skip_bump != "true"`) update `pubspec.yaml`.
5. Run Flutter build + Xcode build + `pilot` upload.
6. Print the `iOS · TestFlight yüklendi` summary box.

## Invocation

```sh
fastlane_cli run ios_internal_bump_deploy --profile <path>
```

For "just build, don't bump" cases:

```sh
fastlane_cli run ios_internal_no_bump_deploy --profile <path>
```

For a dry run (print the materialized fastlane command without spawning):

```sh
fastlane_cli run ios_internal_bump_deploy --profile <path> --dry-run
```

## After the upload

- Build is in TestFlight in "Processing" — usually 5-20 min.
- Once processed, manually (or via an automated rule) attach to the desired
  tester group in App Store Connect.
- The summary box prints the uploaded `version+build` and the IPA path.
  Quote that when reporting back to the user.

## Troubleshooting

- **"Missing password ... non-interactive shell"** → no API key, no session
  cookie; set `APP_STORE_CONNECT_API_KEY_JSON_PATH`.
- **"Invalid build number"** → remote and local diverged in a way that broke
  monotonicity. Re-run a bump action; the lane recomputes `max + 1`.
- **Signing errors** → out of scope for fastlane_cli; verify with
  `xcodebuild` directly.
- Anything else: route to `fastlane-doctor` for a structured diagnostic.

## Do not

- Run `ios_app_store` / `ios_deploy_appstore` when the user only asked for
  TestFlight — those submit to the App Store review queue.
- Bump pubspec manually and then run `ios_internal_bump_deploy` — the bump
  will overwrite the manual edit.
- Disable the summary box or strip it from the relayed output — it is the
  user's primary record of what was uploaded.
