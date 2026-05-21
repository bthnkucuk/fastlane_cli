---
name: fastlane-appstore-promote
description: Promote an already-uploaded TestFlight build to App Store review via fastlane_cli — interactive build picker, no binary re-upload. Triggers on: promote build, promote to app store, submit testflight build, app store review submission, ios_promote_to_app_store, promote_to_app_store, ship existing build, no re-upload.
---

# fastlane_cli — promote a TestFlight build to App Store

Use this skill when the user wants to submit an **already-uploaded**
TestFlight build to the App Store review queue **without** building or
re-uploading a binary. This is distinct from `ios_app_store` /
`ios_deploy_appstore`, which upload a fresh IPA. For a normal TestFlight
upload see [`fastlane-testflight`](../fastlane-testflight/SKILL.md).

## Action / lane

| Action id                  | Lane (`ios`)            | Re-uploads binary? | Confirms? |
| -------------------------- | ----------------------- | ------------------ | --------- |
| `ios_promote_to_app_store` | `promote_to_app_store`  | no                 | yes       |

## What the lane does

1. **Auth** — resolves the App Store Connect API key via the shared
   `resolve_app_store_connect_api_key` helper. An API key is **mandatory**:
   if none is configured the lane fails with a clear remediation message
   instead of falling back to interactive Apple ID. App Store submission
   must be fully API-key driven.
2. **Lists recent TestFlight builds** — queries App Store Connect via
   `Spaceship::ConnectAPI::Build.all` (sorted newest-first, ~20 builds).
   For each build it shows: version string, build number, upload date, and
   processing state (`VALID` / `PROCESSING` / `INVALID`). Non-`VALID`
   builds and builds already attached to an App Store version are clearly
   marked — only `VALID` builds can actually be submitted.
3. **Interactive selection** — prints a numbered list, one build per line,
   then a `Please choose: 1 - N` prompt. In the fastlane_cli TUI this pops
   a selection modal (the `chooseIndex` prompt parser); in a plain
   terminal the user types the number.
4. **Submits for review** — runs `upload_to_app_store` (deliver) with
   `skip_binary_upload: true`, `submit_for_review: true`, `force: true`,
   and the IDFA / export-compliance answers from
   `fastlane/ios/defaults/submission_information.json`.
5. Ends with the `iOS · TestFlight build App Store'a gönderildi` summary
   box (selected build + version, review/release flags, metadata/screenshot
   status, resulting App Store version state).

## Non-interactive override (CI / scripting)

Pass `build_number:` to skip the list + prompt entirely:

```sh
fastlane_cli run ios_promote_to_app_store --profile <path> \
  --option build_number:404
```

The lane still best-effort enriches the build's version/state for the
summary box, and warns if the chosen build is not `VALID`.

## Lane options

| Option               | Default | Effect                                                        |
| -------------------- | ------- | ------------------------------------------------------------- |
| `build_number:`      | (none)  | Skip the picker; promote this build directly (CI override).   |
| `submit_metadata:`   | `false` | Opt in to pushing store metadata alongside the submission.    |
| `submit_screenshots:`| `false` | Opt in to pushing screenshots alongside the submission.       |
| `automatic_release:` | `false` | `true` = auto-release after approval; `false` = manual.       |

By default this lane **promotes a build only** — it does not re-push the
store listing. Use `ios_update_metadata` for metadata changes, or the
`submit_metadata:` / `submit_screenshots:` opt-ins.

## Prerequisites

- App Store Connect API key — `APP_STORE_CONNECT_API_KEY_JSON_PATH`, or the
  `APP_STORE_CONNECT_API_KEY_ID` + `_ISSUER_ID` + `_FILEPATH` triple. A
  `FASTLANE_SESSION` cookie is NOT accepted for this lane.
- Bundle identifier via `app.ios.app_identifier` in `cli_profile.yaml` or
  `IOS_APP_IDENTIFIER` / `FASTLANE_APP_IDENTIFIER` env.
- The target build must already be uploaded to TestFlight and finished
  processing (`VALID`).

## Invocation

```sh
fastlane_cli run ios_promote_to_app_store --profile <path>           # interactive picker
fastlane_cli run ios_promote_to_app_store --profile <path> \
  --option build_number:404                                          # non-interactive
fastlane_cli run ios_promote_to_app_store --profile <path> --dry-run # print, don't run
```

## Do not

- Use this lane to ship a *new* build — it never builds or uploads a
  binary. Use `ios_internal_bump_deploy` (TestFlight) or `ios_app_store`.
- Expect it to work without an API key — interactive Apple ID is
  intentionally unsupported here.
- Strip the summary box from relayed output — it is the user's record of
  what was submitted.
