---
name: fastlane-crashlytics-symbols
description: Upload iOS dSYMs to Firebase Crashlytics via fastlane_cli. iOS path is wired (opt-in flag on the TestFlight lane plus a standalone `upload_dsyms` lane); Android mapping / NDK symbol upload is intentionally not wired and needs a lane extension if requested. Triggers on: crashlytics, dSYM, dsym, upload symbols, upload-symbols, IOS_UPLOAD_SYMBOLS_SCRIPT, firebase symbols, symbolicate, native crash, mapping file, R8 mapping, proguard mapping, NDK symbols, uploadCrashlyticsMappingFile, uploadCrashlyticsSymbolFile.
---

# fastlane_cli — Firebase Crashlytics symbol upload

Use this skill when the user wants Firebase Crashlytics to receive symbol files
so production crashes get symbolicated.

**Asymmetry up front**: iOS dSYM upload is wired into the existing
`test_flight` lane (opt-in flag, default off) and exposed as a dedicated
`upload_dsyms` lane. Android mapping / NDK symbol upload is **not wired** —
no Android lane in this repo calls
`uploadCrashlyticsMappingFile<Variant>` or
`uploadCrashlyticsSymbolFile<Variant>`. If the user asks for Android,
acknowledge the gap and offer to extend the lane.

## Prerequisites (iOS)

Two env vars (script + plist) are mandatory; the third (dSYM path) defaults to
the Flutter xcarchive output.

```sh
# Firebase's upload-symbols binary — ships with the FirebaseCrashlytics pod
# (CocoaPods) or inside the xcframework (SPM). Find it with:
#   find ios -name upload-symbols
export IOS_UPLOAD_SYMBOLS_SCRIPT="ios/Pods/FirebaseCrashlytics/upload-symbols"

export IOS_GOOGLE_SERVICE_INFO_PLIST="ios/Runner/GoogleService-Info.plist"

# Optional — default is ./build/ios/archive/Runner.xcarchive/dSYMs
# export IOS_DSYM_PATH="..."
```

Paths can be relative to the app root — `FastlaneCliConfig.resolve_app_path`
normalises them at lane time. See the canonical list in
[CLAUDE.md](../../CLAUDE.md) §5.3.

**If either script or plist is missing**, the upload step is **soft-skipped**
with a `"atlandı (script/gsp eksik)"` marker on the summary box and a single
`UI.important` warning. The lane itself never hard-fails on a missing symbol
upload — TestFlight upload still succeeds. Quote the marker back to the user
when relaying results so they know symbols did not land.

## iOS — three ways to invoke

### Path A — Bundled into TestFlight upload (recommended)

The `test_flight` lane in [`fastlane/ios/Fastfile`](../../fastlane/ios/Fastfile)
accepts `upload_symbols: "true"` (default `false`). When `true`, it runs
the upload step immediately after `pilot` succeeds. Three base actions all
funnel into this lane (directly or through `internal_test`):

| Action id                  | Lane chain                                         | Add option to enable |
| -------------------------- | -------------------------------------------------- | -------------------- |
| `ios_test_flight`          | `ios test_flight`                                  | `options.upload_symbols: "true"` |
| `ios_internal_bump_deploy` | top-level `internal_test` → `run_subline(:ios, :test_flight, options)` | `options.upload_symbols: "true"` (alongside existing `platform: ios`) |
| `internal_test` (general)  | top-level `internal_test` → same sub-lane for iOS leg | `options.upload_symbols: "true"` |

The general `internal_test` action also drives the Android leg
(`android internal_testing`); `upload_symbols` is harmlessly ignored there
because no Android lane reads it.

Because base actions merge by `id` (full-replace), enabling this in a
consumer profile means copying each action's full block from
`fastlane/cli_profile.base.yaml` and adding the `upload_symbols` option:

```yaml
actions:
  - id: ios_test_flight
    category: ios
    title:
      tr: iOS TestFlight
      en: iOS TestFlight
    description:
      tr: TestFlight yükleme lane'i
      en: TestFlight upload lane
    shortcut: true
    command:
      type: fastlane
      platform: ios
      lane: test_flight
      options:
        upload_symbols: "true"
```

### Path B — Standalone `upload_dsyms` lane

For uploading symbols against an already-archived build without re-uploading
the IPA (e.g. after fixing missing env vars). Defined in
[`fastlane/ios/Fastfile`](../../fastlane/ios/Fastfile) but **not surfaced as a
base action** — consumers must declare one in their `cli_profile.yaml`:

```yaml
actions:
  - id: ios_upload_dsyms
    category: ios
    title:
      tr: iOS dSYM yükle (Crashlytics)
      en: Upload iOS dSYMs (Crashlytics)
    description:
      tr: Firebase Crashlytics'e dSYM yükler, build/upload yapmaz
      en: Uploads dSYMs to Firebase Crashlytics; no build, no store upload
    command:
      type: fastlane
      platform: ios
      lane: upload_dsyms
```

This lane errors hard (`UI.user_error!`) if script or plist is missing — that
is intentional: a standalone symbol upload that silently skips is useless.

### Path C — Upstream change (out of scope for a consumer)

Flipping the lane's default to `upload_symbols: true` is a one-line change in
the core repo. Mention it as an option if the user maintains many app
profiles and wants symbols on everywhere by default — but do not make the
change from a consumer-onboarding context.

## Android — current gap

Neither `android internal_testing`, `android production`, nor
`android firebase_distribute` invoke the Crashlytics Gradle tasks. Two
mechanisms exist outside fastlane_cli that may still cover the user:

- **R8 mapping**: the Firebase Crashlytics Gradle plugin uploads mapping
  files automatically during `bundleRelease` when
  `mappingFileUploadEnabled = true` (default). This happens as a side-effect
  of `flutter build appbundle --release`, before any Fastlane code runs. If
  the user is happy with that, there is nothing for fastlane_cli to do.
- **NDK symbols**: require `./gradlew app:uploadCrashlyticsSymbolFile<Variant>`.
  There is no automatic path — apps with native libraries (`firebase_crashlytics_ndk`
  or hand-written C/C++) will not get symbolicated native crashes without
  this task being run.

If the user requests Android symbol upload, do not invent an action id. Offer
to extend the lane (`internal_testing` / `production` / a new
`upload_crashlytics_symbols` lane) — that is a code change in this repo, not
a profile-only edit.

## After invoking

Quote the summary box's `Symbols` line back to the user. Possible values:

- `Symbols : atlandı` — `upload_symbols` was false (default).
- `Symbols : atlandı (script/gsp eksik)` — flag was true but env missing.
- `Symbols : yüklendi (<dsym path>)` — upload succeeded.

For Path B (`upload_dsyms`) the summary title is `iOS · dSYM yüklendi (Crashlytics)`
and the box lists the script, plist, and dSYM paths used.

## Troubleshooting

- **`upload-symbols: command not found` or `Permission denied`** — the env
  path points at a file that doesn't exist or isn't executable. Re-run
  `find ios -name upload-symbols` and `chmod +x` the result.
- **`Couldn't find a valid project for GoogleAppID`** — `GoogleService-Info.plist`
  is the wrong one (e.g. dev vs prod). Crashlytics keys are app-id-scoped.
- **dSYMs missing from the xcarchive** — Flutter release builds default to
  `dwarf-with-dsym`; if a custom `--no-codesign` or `--debug-info=…` flag is
  in use, the path resolves to an empty directory. Verify with
  `ls -l "$IOS_DSYM_PATH"` before invoking.
- **Bitcode-recompiled symbols (legacy)** — Apple no longer accepts bitcode
  uploads (Xcode 14+), so dSYMs from the local archive are the only set.
  Don't chase the "download dSYMs from App Store Connect" path.

## Do not

- Tell the user Android Crashlytics upload "works" — it doesn't, from this
  repo. Acknowledge the gap.
- Hardcode `GoogleService-Info.plist` paths into base lanes or this repo —
  app-specific, must come from the consumer's env / profile.
- Add `IOS_UPLOAD_SYMBOLS_SCRIPT` to fastlane_cli's repo `.env.example` with
  a concrete path — the path is project-layout-dependent (Pods vs SPM vs
  custom). Document only the variable name and the `find` command.
- Strip the `Symbols` line from the summary when relaying results.
