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
fastlane_cli doctor --profile <path-to-cli_profile.yaml>
```

(`doctor` is part of [ROADMAP.md](../../ROADMAP.md) §2; once landed, it
validates the items below in order.)

What it checks:

- `fastlane --version` resolves and is current enough.
- Ruby ≥ 3.2.
- `BUNDLE_PATH` / `BUNDLE_GEMFILE` correctly set; bundle has been installed
  into the user-cache location.
- `cli_profile.yaml` exists, parses, and the merge against
  `cli_profile.base.yaml` produces a non-empty action list.
- Required env vars for any platform declared in `app.<platform>`:
  - iOS — at least one valid App Store Connect credential source.
  - Android — `GOOGLE_PLAY_JSON_KEY_PATH` is set and the file exists.

## Symptom → likely cause table

| Symptom (from log / TUI)                                              | Likely cause                                                                                          | Fix                                                                                                                                  |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `fastlane: command not found`                                         | Fastlane not installed (brew dep missing or not on `PATH`).                                            | `brew install fastlane`, ensure `$(brew --prefix)/bin` is in `PATH`.                                                                 |
| `Could not find ... in any of the sources` (bundler)                  | Bundle not installed into the user cache.                                                              | `fastlane_cli doctor` (auto-installs), or manually `bundle install --gemfile=<fastlane_cli runner>/Gemfile`.                         |
| `Your Ruby version is X.Y, but your Gemfile specified ...`            | Ruby < 3.2 or version mismatch.                                                                       | Install Ruby 3.2 via rbenv / asdf / Homebrew, re-shim.                                                                               |
| `Missing password ... non-interactive shell` (iOS)                    | No App Store Connect API key set; lane fell back to FASTLANE_USER + FASTLANE_PASSWORD; stdin closed.    | Set `APP_STORE_CONNECT_API_KEY_JSON_PATH` *or* `APP_STORE_CONNECT_API_KEY_ID` + `_ISSUER_ID` + `_FILEPATH`.                          |
| `Invalid API key` (iOS)                                               | JSON path wrong / file content malformed / key revoked in App Store Connect.                            | Regenerate the API key, point `APP_STORE_CONNECT_API_KEY_JSON_PATH` at the new JSON.                                                 |
| `The caller does not have permission` (Android)                       | Service account lacks Release manager role, or not added in Play Console → Setup → API access.          | Add the service account to the app and grant Release manager.                                                                        |
| `GOOGLE_PLAY_JSON_KEY_PATH not set` / file not found                  | Env var missing or path doesn't exist.                                                                  | `export GOOGLE_PLAY_JSON_KEY_PATH=/abs/path/to/play-service-account.json`.                                                            |
| `Missing ANDROID identifier` / `Missing IOS identifier`               | Neither profile (`app.<platform>.app_identifier` / `package_name`) nor env supplies the id.             | Add the identifier to `cli_profile.yaml`, or set `IOS_APP_IDENTIFIER` / `ANDROID_PACKAGE_NAME` / `FASTLANE_APP_IDENTIFIER`.          |
| `Could not parse version from <pubspec.yaml>`                         | `pubspec.yaml` `version:` line doesn't match `X.Y.Z+N`.                                                 | Hand-edit pubspec to a valid `version: 1.0.0+1` shape, then re-run.                                                                  |
| `versionCode N has already been used` (Android)                       | Local `+N` collides with what's already on Play.                                                        | Run a bump action (e.g. `android_internal_bump_deploy`) — it recomputes `max + 1`.                                                   |
| `Invalid build number` (iOS)                                          | Local + iTC drifted; current local <= last uploaded.                                                    | Run a bump action (e.g. `ios_internal_bump_deploy`) — it recomputes `max + 1`.                                                       |
| `AAB not found at ...`                                                | `flutter build appbundle --release` hasn't been run, or flavor mismatch.                                | Run flutter build manually; verify `FASTLANE_FLAVOR` matches the gradle flavor.                                                      |
| `IPA not found at ...`                                                | `flutter build ipa` / Xcode export hasn't been run, or `IOS_IPA_PATH` / `IOS_IPA_NAME` wrong.           | Run flutter build manually; verify `IOS_IPA_PATH` if non-default.                                                                    |
| `fastlane runner not found` (Dart side)                               | Pre-ROADMAP §1 build and profile is missing `fastlane_runner_path`.                                     | Add `fastlane_runner_path: /abs/path/to/fastlane_cli/fastlane` to the profile, *or* upgrade fastlane_cli to a version with §1 landed.|
| `cli_profile.yaml` not found                                          | Path passed to `--profile` is wrong.                                                                    | Use an absolute path. Default convention: profile sits at the Flutter project root.                                                  |
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
- Suggest hand-editing the bundled `fastlane/Gemfile` or `cli_profile.base.yaml`
  in this repo to "fix" a per-app issue. Per-app overrides go in the
  consumer's `cli_profile.yaml`.
- Quote action ids you haven't seen in this profile's `fastlane_cli list
  --json` output when describing a fix.
