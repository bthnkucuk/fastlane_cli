---
name: fastlane-version-bump
description: Inspect or bump the Flutter app's pubspec `version: X.Y.Z+N` and reconcile it with the Android Play track and the App Store Connect build number. Triggers on: version, bump, version code, build number, version status, increment, what's the current version, pubspec version.
---

# fastlane_cli — version status & bumps

Use this skill when the user wants to **see** or **change** the app's
version. There are two distinct flows: status-only queries (read remote +
local, no writes) and bump-and-deploy flows (mutate pubspec + ship a build).

## Discover the active actions first

Run `fastlane_cli list --json --profile <path>` and confirm which of the
following base actions are present in the user's profile (a per-app profile
may rename, replace, or remove any of them). The ids below are the ones
shipped in `fastlane/cli_profile.base.yaml`.

## Read-only: "what version are we on?"

| Action id            | Lane              | Reads                                                                         |
| -------------------- | ----------------- | ----------------------------------------------------------------------------- |
| `get_version_data`   | `get_version_data` (top-level)   | `pubspec.yaml`, iOS Info.plist, Android `build.gradle`, App Store Connect, Google Play |
| `android_version_status` | `version_status` (android) | `pubspec.yaml` + Google Play track versionCodes                              |

`get_version_data` is the all-in-one summary; `android_version_status` is the
Android-only deep dive. Both end with the canonical coloured summary box.

Invocation:

```sh
fastlane_cli run get_version_data --profile <path>
fastlane_cli run android_version_status --profile <path>
```

## Mutating: "bump and deploy"

The only base actions that bump pubspec are:

| Action id                       | Lane (top-level)  | What it does                                                                |
| ------------------------------- | ----------------- | --------------------------------------------------------------------------- |
| `internal_test`                 | `internal_test`   | Bumps pubspec (patch + build), then builds + uploads for *both* platforms.   |
| `android_internal_bump_deploy`  | `internal_test` (`platform: android`) | Same bump, Android only → Play internal track.                              |
| `ios_internal_bump_deploy`      | `internal_test` (`platform: ios`)     | Same bump, iOS only → TestFlight.                                           |
| `android_internal_no_bump_deploy` | `internal_test` (`platform: android`, `skip_bump: "true"`) | Builds + uploads current pubspec version — does **not** bump.               |
| `ios_internal_no_bump_deploy`   | `internal_test` (`platform: ios`, `skip_bump: "true"`)     | Builds + uploads current pubspec version — does **not** bump.               |

All five flow through the top-level `internal_test` lane; the only differences
are the `platform` and `skip_bump` options.

### How the bump is computed

- pubspec `version: X.Y.Z+N` is parsed.
- `Z` (patch) is incremented by 1.
- `N` (build number) is set to `max(android_play_version_code, ios_build_number, pubspec_build_number) + 1`.
  The actual rule and the source of each piece is printed in the lane's
  summary box — quote that, don't reverse-engineer it.

### Confirmation

All five mutating actions have `requires_confirmation: true` (except the
`no_bump` variants, which only deploy). Surface that the user is about to
write to remote store tracks before running.

## When the user only wants to set a specific value

There is no base action that takes a literal "set pubspec to 1.2.3+45"
argument. The `storepilot_bridge.rb` command
`development_update_pubspec_version` does this and is invoked internally by
some lanes; it is not exposed as a `fastlane_cli run` action. Tell the user
to either bump via the normal flow or, in advanced cases, edit `pubspec.yaml`
manually and then run an `*_internal_no_bump_deploy` action.

## Common questions

- **"Bump only, don't deploy"** — not a separate base action. Closest paths:
  edit pubspec manually, or run `internal_test` and cancel before upload
  (not recommended — partial state). If this comes up often, the user may
  add a custom action to their profile.
- **"Reset version code"** — never do this for already-published builds;
  Play / App Store require monotonically increasing build numbers.

## Env vars you may need

See `CLAUDE.md` §5.3:

- `APP_STORE_CONNECT_API_KEY_JSON_PATH` or the id/issuer/p8 triple (iOS read
  of current build number).
- `GOOGLE_PLAY_JSON_KEY_PATH` (Android read of current versionCode).
- `FASTLANE_PUBSPEC_PATH` — only if `pubspec.yaml` is not at the project root.

If credentials are missing, `get_version_data` falls back to local-only
sources and the summary box reports `(remote unavailable)` per platform.

## Do not

- Hand-edit `pubspec.yaml` and *also* run a bump action in the same flow —
  the bump will overwrite your edit.
- Suggest decrementing the build number.
- Quote any action id you haven't observed in this profile's
  `fastlane_cli list --json` output.
