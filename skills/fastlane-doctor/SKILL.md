---
name: fastlane-doctor
description: Diagnose fastlane_cli env/credential/toolchain issues before invoking a lane. Triggers on: doctor, diagnose, troubleshoot, why isn't it working, credentials check, env check, fastlane_cli doctor, "missing API key", "permission denied", "bundle install", "ruby version".
---

# fastlane_cli — doctor / diagnostics

Use this skill when a lane fails to start, fails authentication, or the user
asks "is everything set up correctly?". The diagnostics flow is:

1. Run the built-in checker.
2. Walk the symptom → cause table below.
3. Apply the minimal fix and re-run.

## Built-in checker

```sh
fastlane_cli doctor                              # auto-resolve profile
fastlane_cli doctor --profile <path>             # explicit profile
```

`doctor` resolves the profile best-effort — a missing profile is non-fatal
(only the credential block needs it), so `fastlane_cli doctor` runs even
before a `profile.yaml` exists. It prints a coloured `[OK]` / `[WARN]` /
`[FAIL]` report ending with an `N OK · N warnings · N errors` tally, and
exits `1` if any check failed, `0` otherwise — so it is CI-gateable.

What it checks (each row is one `[OK]` / `[WARN]` / `[FAIL]` entry):

- `fastlane` — `fastlane --version` resolves.
- `ruby` — Ruby is on PATH and ≥ 3.2.
- `bundle cache` — the gem bundle has been installed into the user-cache
  location (`~/Library/Caches/fastlane_cli/bundle/...`).
- `app root` / `fastlane dir` — when a profile loaded, the resolved app root
  and fastlane data folder exist on disk.
- iOS credentials + bundle id — added when the profile has any iOS action
  (id prefixed `ios_` or `command.platform: ios`): at least one App Store
  Connect credential source, and one of the iOS identifier env vars.
- Android credentials + package — added when the profile has any Android
  action: `GOOGLE_PLAY_JSON_KEY_PATH` set, and one of the Android identifier
  env vars.

Note: the credential / identifier rows are **env-var checks** — `doctor`
reads `IOS_APP_IDENTIFIER` / `ANDROID_PACKAGE_NAME` / `FASTLANE_APP_IDENTIFIER`
from the environment, not `app.package_name` / `app.bundle_id` from the
profile. A profile that supplies identity only via `app.bundle_id` will still
show a `[WARN]` identifier row — that is expected; the lane itself resolves
the profile value fine.

## Symptom → likely cause table

| Symptom (from log / TUI)                                              | Likely cause                                                                                          | Fix                                                                                                                                  |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `fastlane: command not found`                                         | Fastlane not installed (brew dep missing or not on `PATH`).                                            | `brew install fastlane`, ensure `$(brew --prefix)/bin` is in `PATH`.                                                                 |
| `Could not find ... in any of the sources` (bundler)                  | Bundle not installed into the user cache.                                                              | Re-run any lane — first-run setup auto-installs the bundle; `fastlane_cli doctor` reports the `bundle cache` row so you can confirm.  |
| `Your Ruby version is X.Y, but your Gemfile specified ...`            | Ruby < 3.2 or version mismatch.                                                                       | Install Ruby 3.2 via rbenv / asdf / Homebrew, re-shim.                                                                               |
| `Missing password ... non-interactive shell` (iOS)                    | No App Store Connect API key set; lane fell back to FASTLANE_USER + FASTLANE_PASSWORD; stdin closed.    | Set `APP_STORE_CONNECT_API_KEY_JSON_PATH` *or* `APP_STORE_CONNECT_API_KEY_ID` + `_ISSUER_ID` + `_FILEPATH`.                          |
| `Invalid API key` (iOS)                                               | JSON path wrong / file content malformed / key revoked in App Store Connect.                            | Regenerate the API key, point `APP_STORE_CONNECT_API_KEY_JSON_PATH` at the new JSON.                                                 |
| `The caller does not have permission` (Android)                       | Service account lacks Release manager role, or not added in Play Console → Setup → API access.          | Add the service account to the app and grant Release manager.                                                                        |
| `GOOGLE_PLAY_JSON_KEY_PATH not set` / file not found                  | Env var missing or path doesn't exist.                                                                  | `export GOOGLE_PLAY_JSON_KEY_PATH=/abs/path/to/play-service-account.json`.                                                            |
| `Missing ANDROID identifier` / `Missing IOS identifier`               | Neither profile (`app.package_name` / `app.bundle_id`) nor env supplies the id.                         | Add `app.package_name` / `app.bundle_id` to `profile.yaml`, or set `IOS_APP_IDENTIFIER` / `ANDROID_PACKAGE_NAME` / `FASTLANE_APP_IDENTIFIER`. |
| `Could not parse version from <pubspec.yaml>`                         | `pubspec.yaml` `version:` line doesn't match `X.Y.Z+N`.                                                 | Hand-edit pubspec to a valid `version: 1.0.0+1` shape, then re-run.                                                                  |
| `versionCode N has already been used` (Android)                       | Local `+N` collides with what's already on Play.                                                        | Run a bump action (e.g. `android_internal_bump_deploy`) — it recomputes `max + 1`.                                                   |
| `Invalid build number` (iOS)                                          | Local + iTC drifted; current local <= last uploaded.                                                    | Run a bump action (e.g. `ios_internal_bump_deploy`) — it recomputes `max + 1`.                                                       |
| `AAB not found at ...`                                                | `flutter build appbundle --release` hasn't been run, or flavor mismatch.                                | Run flutter build manually; verify `FASTLANE_FLAVOR` matches the gradle flavor.                                                      |
| `IPA not found at ...`                                                | `flutter build ipa` / Xcode export hasn't been run, or `IOS_IPA_PATH` / `IOS_IPA_NAME` wrong.           | Run flutter build manually; verify `IOS_IPA_PATH` if non-default.                                                                    |
| `fastlane runner not found` (Dart side)                               | The bundled runner could not be auto-resolved (corrupt install, or `dart run` from outside the repo).   | Reinstall via brew, or set `app.fastlane_runner_path` to a directory containing a `Fastfile` (see `fastlane-cli-layout`).            |
| `Could not locate profile.yaml`                                       | No profile via `--profile`, `$FASTLANE_CLI_PROFILE`, walk-up, or cwd.                                   | Pass `--profile <path>` (file or app dir), export `$FASTLANE_CLI_PROFILE`, or run from inside a `pubspec.yaml` + `fastlane/profile.yaml` app. See `fastlane-cli-layout`. |
| Lane runs but no summary box at the end                               | Lane authored without `FastlaneCliConfig.print_summary_box`.                                            | See the `fastlane-summary-log` skill — every user-facing lane MUST end with one.                                                     |

## Env var sanity check (quick manual one-liner)

```sh
printenv | grep -E '^(APP_STORE_CONNECT_|GOOGLE_PLAY_JSON_KEY_PATH|IOS_APP_IDENTIFIER|ANDROID_PACKAGE_NAME|FASTLANE_APP_IDENTIFIER|FASTLANE_FLAVOR|FASTLANE_PUBSPEC_PATH)='
```

Confirm:

- exactly one App Store Connect credential set is present (don't mix JSON +
  triple);
- the JSON / `.p8` files exist on disk (`ls -l "$APP_STORE_CONNECT_API_KEY_JSON_PATH"`);
- `GOOGLE_PLAY_JSON_KEY_PATH` points to a real JSON, not a placeholder.

## When to escalate beyond doctor

- Code signing failures (iOS) — out of fastlane_cli scope; use `xcodebuild` /
  `match` directly.
- Gradle / Java toolchain errors — out of scope; verify with
  `./gradlew bundleRelease` from the `android/` folder.
- Play / App Store policy rejections — the summary box surfaces the API
  response; the actual fix is product-side, not CLI-side.

## Do not

- Suggest `sudo` for anything fastlane_cli-related. Bundle install lives in
  the user cache; you should never need root.
- Suggest hand-editing the bundled `fastlane/Gemfile` or `profile.base.yaml`
  in this repo to "fix" a per-app issue. Per-app overrides go in the
  consumer's `profile.yaml`.
- Quote action ids you haven't seen in this profile's `fastlane_cli list
  --json` output when describing a fix.
