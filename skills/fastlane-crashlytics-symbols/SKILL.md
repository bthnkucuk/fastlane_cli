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

## Prerequisites (iOS) — zero-config since v0.8.0

The `upload-symbols` binary and the `GoogleService-Info.plist` are
**auto-discovered at runtime**. A standard SwiftPM-Firebase app needs **no
Crashlytics env vars at all**.

`upload-symbols` discovery precedence (first existing hit wins):

1. **Explicit override** — `IOS_UPLOAD_SYMBOLS_SCRIPT` env var (or the
   `upload_symbols_script` option).
2. **CocoaPods** — `ios/Pods/FirebaseCrashlytics/upload-symbols`.
3. **SwiftPM DerivedData** — globs
   `~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols`,
   picks the most-recently-modified match (newest build), then **copies it to
   a stable per-user cache** at `~/Library/Caches/fastlane_cli/upload-symbols`
   and uses the cached path. The volatile DerivedData hash never reaches the
   actual `sh` call, so a later DerivedData wipe doesn't break a re-run.
4. **Vendored** — `ios/scripts/upload-symbols` (some repos vendor a copy).
5. Nothing → soft-skip.

`GoogleService-Info.plist` discovery precedence:

1. **Explicit override** — `IOS_GOOGLE_SERVICE_INFO_PLIST` env var (or the
   `google_service_info_plist` option).
2. **Flavor convention** — `ios/flavors/<flavor>/GoogleService-Info.plist`
   when a flavor resolves.
3. **Default** — `ios/Runner/GoogleService-Info.plist`.
4. Nothing → soft-skip.

```sh
# Optional overrides — only needed for non-standard layouts. A standard
# SwiftPM-Firebase + ios/flavors/<flavor>/GoogleService-Info.plist app
# needs NONE of these.
# export IOS_UPLOAD_SYMBOLS_SCRIPT="ios/Pods/FirebaseCrashlytics/upload-symbols"
# export IOS_GOOGLE_SERVICE_INFO_PLIST="ios/Runner/GoogleService-Info.plist"

# Optional — default is ./build/ios/archive/Runner.xcarchive/dSYMs
# export IOS_DSYM_PATH="..."
```

Override paths can be relative to the app root — `FastlaneCliConfig.resolve_app_path`
normalises them at lane time. See the canonical list in
[CLAUDE.md](../../CLAUDE.md) §5.3.

**If discovery resolves nothing**, the `test_flight` upload step is
**soft-skipped** with a `"atlandı (upload-symbols bulunamadı)"` or
`"atlandı (GoogleService-Info.plist bulunamadı)"` marker on the summary box and
a single `UI.important` warning. The lane itself never hard-fails on a missing
symbol upload — TestFlight upload still succeeds. Quote the marker back to the
user when relaying results so they know symbols did not land.

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

For a one-off run without editing the profile, pass the flag straight on the
command line — `--option` uses `=` as the separator:

```sh
fastlane_cli run ios_test_flight --option upload_symbols=true
fastlane_cli run internal_test --option upload_symbols=true --option obfuscate=true
```

Persist it across runs by adding `upload_symbols: "true"` to `default_options`
in the consumer `profile.yaml` — that enables symbol upload on both platforms
at once.

Because base actions merge by `id` (full-replace), enabling this in a
consumer profile means copying each action's full block from
`fastlane/profile.base.yaml` and adding the `upload_symbols` option:

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
base action** — consumers must declare one in their `profile.yaml`:

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

This lane errors hard (`UI.user_error!`) if auto-discovery cannot locate the
`upload-symbols` binary or the `GoogleService-Info.plist` — that is
intentional: a standalone symbol upload that silently skips is useless. The
error message lists every discovery tier that was checked.

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
- **NDK native symbols** — wired (since v0.9.0). The `internal_testing` and
  `production` lanes in
  [`fastlane/android/Fastfile`](../../fastlane/android/Fastfile), when
  `upload_symbols: "true"`, run the Crashlytics native-symbol Gradle task
  after the AAB build, via the `upload_crashlytics_ndk_symbols` private lane.

### The Gradle task

The task is `uploadCrashlyticsSymbolFile<Flavor>Release`, built by the pure
helper `FastlaneCliConfig.crashlytics_symbol_task(flavor:, build_type:)`:

| Flavor (`resolve_flavor`) | Task name                                  |
| ------------------------- | ------------------------------------------ |
| `staging`                 | `uploadCrashlyticsSymbolFileStagingRelease` |
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

## Flutter Dart-obfuscation symbols (both platforms, since v0.11.0)

A release built with `--obfuscate --split-debug-info=<dir>` (driven by the
`obfuscate` profile option — see `FastlaneCliConfig.flutter_build_flags`)
writes **Dart** symbol mapping files into `<dir>`. These are separate from
the iOS dSYMs and the Android NDK native symbols above — without uploading
them, **Dart** crash stack traces stay obfuscated.

The Dart symbol upload is wired into the Android `internal_testing` /
`production` lanes and the iOS `test_flight` lane, via the shared
`FastlaneCliConfig.upload_flutter_symbols(options, platform:)` method.

### Gate — `obfuscate` AND `upload_symbols`

It acts only when **BOTH** `obfuscate: "true"` **AND** `upload_symbols: "true"`
are set (the same `upload_symbols` flag that drives dSYM / NDK upload). If
either is off it is a neutral no-op (`Dart symbols : atlandı`). This makes
sense: there are no Dart symbols to upload unless the build was obfuscated.

### Prerequisites

- The **`firebase` CLI** must be on PATH (`npm i -g firebase-tools` or
  `brew install firebase-cli`). fastlane_cli soft-skips if it is absent.
- A **Firebase app id**, resolved from the `firebase_app_id` option →
  `FIREBASE_APP_ID_ANDROID` (android) / `FIREBASE_APP_ID_IOS` (ios) env var.

```sh
export FIREBASE_APP_ID_ANDROID="1:1234567890:android:abcdef"
export FIREBASE_APP_ID_IOS="1:1234567890:ios:abcdef"
```

### The command

On the happy path the helper runs, from the app root, wrapped in
`with_clean_subprocess_env`:

```sh
firebase crashlytics:symbols:upload --app=<FIREBASE_APP_ID> <split-debug-info-dir>
```

`<split-debug-info-dir>` is the SAME directory `--split-debug-info` wrote to
(the `split_debug_info` option, default `build/symbols`) — `flutter_build_flags`
and `upload_flutter_symbols` share one resolver so they never diverge.

### Soft-skip behaviour

Like the dSYM / NDK steps, this never hard-fails the release. It soft-skips
(and the build + store upload still succeed) when the `firebase` CLI is
absent, the split-debug-info directory is missing/empty, no Firebase app id
resolves, or the `firebase` upload exits non-zero.

## After invoking

Quote the summary box's symbols line back to the user.

**iOS** `test_flight` — `Symbols` line:

- `Symbols : atlandı` — `upload_symbols` was false (default).
- `Symbols : atlandı (upload-symbols bulunamadı)` — flag was true but the
  binary could not be discovered (no Pods, no SwiftPM DerivedData, no override).
- `Symbols : atlandı (GoogleService-Info.plist bulunamadı)` — flag was true but
  no plist could be discovered.
- `Symbols : yüklendi (kaynak: <source>)` — upload succeeded. `<source>` is
  one of `explicit override`, `CocoaPods`, `SwiftPM DerivedData`,
  `SwiftPM DerivedData → cache`, `vendored (ios/scripts)` — so the user can see
  WHERE the binary was found.

For Path B (`upload_dsyms`) the summary title is `iOS · dSYM yüklendi (Crashlytics)`
and the box lists the script, the script source, the plist, and the dSYM paths used.

**Android** `internal_testing` / `production` — `NDK symbols` line:

- `NDK symbols : atlandı` — `upload_symbols` was false (default).
- `NDK symbols : atlandı (uploadCrashlyticsSymbolFile task yok / nativeSymbolUploadEnabled kapalı)`
  — flag was true but the gradle task is absent (no Crashlytics plugin,
  `nativeSymbolUploadEnabled` off, or no native code). The AAB still
  uploaded; only symbols were skipped.
- `NDK symbols : yüklendi (<task>)` — upload succeeded; `<task>` is the exact
  `uploadCrashlyticsSymbolFile<Flavor>Release` task that ran.

**Both platforms** — `Dart symbols` line (Flutter obfuscation symbols):

- `Dart symbols : atlandı` — `obfuscate` and/or `upload_symbols` was false
  (the gate did not open). No Dart symbols to upload.
- `Dart symbols : atlandı (firebase CLI yok)` — the gate opened but the
  `firebase` CLI is not on PATH.
- `Dart symbols : atlandı (split-debug-info dizini boş)` — the
  `--split-debug-info` directory is missing or empty (no obfuscated build
  artefacts found).
- `Dart symbols : atlandı (Firebase app id yok)` — no `firebase_app_id`
  option and no `FIREBASE_APP_ID_ANDROID` / `FIREBASE_APP_ID_IOS` env var.
- `Dart symbols : atlandı (firebase symbols:upload başarısız)` — the
  `firebase crashlytics:symbols:upload` invocation exited non-zero.
- `Dart symbols : yüklendi (flutter symbols)` — upload succeeded.

## Troubleshooting

- **`upload-symbols: command not found` or `Permission denied`** — an explicit
  override points at a file that doesn't exist or isn't executable, or
  auto-discovery cached a non-executable copy. The cache copy is `chmod 0755`-ed
  on write; if the source binary was bad, delete
  `~/Library/Caches/fastlane_cli/upload-symbols` and re-run so discovery
  re-copies. For non-standard layouts, set `IOS_UPLOAD_SYMBOLS_SCRIPT`
  explicitly after `chmod +x` the binary.
- **upload-symbols not found at all** — for a SwiftPM-Firebase app, do a
  clean build first so DerivedData contains the `firebase-ios-sdk` checkout;
  auto-discovery globs DerivedData for it. For a CocoaPods app, run
  `pod install`.
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
- Tell the user to hand-`cp` the `upload-symbols` binary out of DerivedData
  and pin `IOS_UPLOAD_SYMBOLS_SCRIPT` — that is exactly the fragile workflow
  v0.8.0's auto-discovery + per-user cache removed. Mention the env vars only
  as overrides for non-standard layouts.
- Add `IOS_UPLOAD_SYMBOLS_SCRIPT` to fastlane_cli's repo `.env.example` with
  a concrete path — the path is project-layout-dependent (Pods vs SPM vs
  custom), and auto-discovery handles the standard layouts anyway.
- Strip the `Symbols` line from the summary when relaying results.
