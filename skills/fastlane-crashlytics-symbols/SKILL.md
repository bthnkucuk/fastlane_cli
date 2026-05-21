---
name: fastlane-crashlytics-symbols
description: Upload iOS dSYMs and Android NDK native symbols to Firebase Crashlytics via fastlane_cli. iOS path is wired (opt-in flag on the TestFlight lane plus a standalone `upload_dsyms` lane); Android NDK symbol upload is wired into the `internal_testing` / `production` lanes via the same `upload_symbols` flag. Triggers on: crashlytics, dSYM, dsym, upload symbols, upload-symbols, IOS_UPLOAD_SYMBOLS_SCRIPT, firebase symbols, symbolicate, native crash, mapping file, R8 mapping, proguard mapping, NDK symbols, nativeSymbolUploadEnabled, uploadCrashlyticsMappingFile, uploadCrashlyticsSymbolFile.
---

# fastlane_cli — Firebase Crashlytics symbol upload

Use this skill when the user wants Firebase Crashlytics to receive symbol files
so production crashes get symbolicated.

**Both platforms are wired**, driven by ONE shared flag — `upload_symbols`:

- **iOS** — `upload_symbols: "true"` on the `test_flight` lane uploads dSYMs
  (also exposed as a standalone `upload_dsyms` lane).
- **Android** — `upload_symbols: "true"` on the `internal_testing` /
  `production` lanes runs the NDK native-symbol Gradle task after the AAB
  build. The R8/Kotlin mapping file needs nothing — the Firebase Crashlytics
  Gradle plugin uploads it automatically during the release build.

A profile that already carries `upload_symbols: "true"` in `default_options`
enables Crashlytics symbol upload on BOTH platforms with no further change.

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
(`android internal_testing`); `upload_symbols` is **also honoured there** —
the same flag triggers Android NDK symbol upload (see the Android section).

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

## Android — NDK native symbols

Two separate mechanisms, only one of which fastlane_cli touches:

- **R8/Kotlin mapping** — uploaded automatically by the Firebase Crashlytics
  Gradle plugin during `bundleRelease` (a side-effect of
  `flutter build appbundle --release`), when `mappingFileUploadEnabled` is
  true (the plugin default). fastlane_cli does **nothing** for it.
- **NDK native symbols** — wired (since v0.8.0). The `internal_testing` and
  `production` lanes in
  [`fastlane/android/Fastfile`](../../fastlane/android/Fastfile), when
  `upload_symbols: "true"`, run the Crashlytics native-symbol Gradle task
  after the AAB build, via the `upload_crashlytics_ndk_symbols` private lane.

### The Gradle task

The task is `uploadCrashlyticsSymbolFile<Flavor>Release`, built by the pure
helper `FastlaneCliConfig.crashlytics_symbol_task(flavor:, build_type:)`:

| Flavor (`resolve_flavor`) | Task name                                  |
| ------------------------- | ------------------------------------------ |
| `narravo`                 | `uploadCrashlyticsSymbolFileNarravoRelease` |
| `freeStaging`             | `uploadCrashlyticsSymbolFileFreeStagingRelease` |
| _(none)_                  | `uploadCrashlyticsSymbolFileRelease`       |

Only the first letter of each segment is capitalised — Gradle variant
casing, not title-case. The lane invokes:

```sh
cd <app-root> && ./android/gradlew -p android :app:<task> --stacktrace
```

wrapped in `with_clean_subprocess_env` (same GEM_HOME scrub as the flutter
shell-outs — gradle transitively spawns tooling).

### App-side prerequisite (the consumer must add this)

The Gradle task only exists if the consumer app enables native symbol
upload. In each `android/app/build.gradle.kts`, inside the release build
type:

```kotlin
android {
    buildTypes {
        release {
            // ...existing release config...
            firebaseCrashlytics {
                nativeSymbolUploadEnabled = true
            }
        }
    }
}
```

(Groovy `build.gradle` equivalent: `firebaseCrashlytics { nativeSymbolUploadEnabled true }`.)
This requires the `com.google.firebase.crashlytics` Gradle plugin to be
applied. fastlane_cli does NOT and MUST NOT edit consumer apps — this is the
user's one-time setup step.

### Soft-skip behaviour

If the task does not exist — the app has not applied the Crashlytics plugin,
`nativeSymbolUploadEnabled` is false, or the app simply has no native code —
the gradle invocation errors. The lane **catches the error and soft-skips**:
it sets the summary marker to
`atlandı (uploadCrashlyticsSymbolFile task yok / nativeSymbolUploadEnabled kapalı)`
and the AAB build + Play Store upload still succeed. NDK symbol upload never
hard-fails the lane — mirrors the iOS `symbols_status` philosophy.

## After invoking

Quote the summary box's symbols line back to the user.

**iOS** `test_flight` — `Symbols` line:

- `Symbols : atlandı` — `upload_symbols` was false (default).
- `Symbols : atlandı (script/gsp eksik)` — flag was true but env missing.
- `Symbols : yüklendi (<dsym path>)` — upload succeeded.

For Path B (`upload_dsyms`) the summary title is `iOS · dSYM yüklendi (Crashlytics)`
and the box lists the script, plist, and dSYM paths used.

**Android** `internal_testing` / `production` — `NDK symbols` line:

- `NDK symbols : atlandı` — `upload_symbols` was false (default).
- `NDK symbols : atlandı (uploadCrashlyticsSymbolFile task yok / nativeSymbolUploadEnabled kapalı)`
  — flag was true but the gradle task is absent (no Crashlytics plugin,
  `nativeSymbolUploadEnabled` off, or no native code). The AAB still
  uploaded; only symbols were skipped.
- `NDK symbols : yüklendi (<task>)` — upload succeeded; `<task>` is the exact
  `uploadCrashlyticsSymbolFile<Flavor>Release` task that ran.

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

- Tell the user Android NDK symbols upload without the app-side
  `firebaseCrashlytics { nativeSymbolUploadEnabled = true }` — without it the
  Gradle task does not exist and the lane soft-skips. Always state the
  prerequisite.
- Hardcode `GoogleService-Info.plist` paths or Android flavor names into base
  lanes or this repo — app-specific, must come from the consumer's env /
  profile (`resolve_flavor`).
- Edit a consumer app's `build.gradle.kts` from fastlane_cli — the
  `nativeSymbolUploadEnabled` line is the user's one-time setup.
- Add `IOS_UPLOAD_SYMBOLS_SCRIPT` to fastlane_cli's repo `.env.example` with
  a concrete path — the path is project-layout-dependent (Pods vs SPM vs
  custom). Document only the variable name and the `find` command.
- Strip the `Symbols` line from the summary when relaying results.
