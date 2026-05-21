# CLAUDE.md

Guidance for Claude Code / Cursor working inside the **fastlane_cli** repo.

This is a standalone Dart CLI that drives Fastlane lanes for any Flutter app
through a categorized, terminal-first UI. It was extracted from a private
monorepo at commit `9d24baa7e` of that repo (see [ROADMAP.md](ROADMAP.md)).

End goal: ship as a Homebrew-installable CLI (`brew install fastlane_cli`) so
any Flutter project can drop a `profile.yaml` next to its own `fastlane/`
folder and run lanes without bundling a Ruby/Fastlane runner.

---

## 1. Layout

```
bin/                    # Dart entrypoint(s)
  fastlane_cli.dart     # main()
  sync_metadata_fallbacks.rb  # ruby helper invoked by lanes

lib/
  fastlane_cli.dart     # public library export
  src/
    bootstrap/          # FastlaneCliLauncher
    localization/       # slang i18n (tr/en), locale_code, run_status_label
    model/              # CliProfile, CliAction, CommandRequest, ...
    routing/            # zenrouter Coordinator + routes
    services/           # CommandBuilder, ProfileLoader, GuideRegistry, ...
    ui/                 # nocterm components

fastlane/               # The Ruby/Fastlane runner that the Dart binary invokes
  Fastfile              # top-level entry (delegates to ios/Fastfile, android/Fastfile)
  ios/Fastfile          # iOS lanes (TestFlight, App Store, metadata)
  android/Fastfile      # Android lanes (Play Console, metadata)
  common_helpers.rb     # FastlaneCliConfig helpers (option resolution, env, summary_box, ...)
  storepilot_bridge.rb  # JSON-over-stdout bridge for app/metadata queries
  profile.base.yaml # Shared shortcuts/categories/actions merged into every app profile
  actions/              # Custom fastlane actions
  ios/defaults/         # default review_information / submission / privacy templates
  vendor/               # GITIGNORED — `bundle install --path vendor/bundle` output (will move to user cache; see ROADMAP)

test/                   # Dart unit tests (mocktail, package:test)
```

`fastlane/vendor/` is intentionally git-ignored and ~111 MB locally. The
brew-distribution plan moves bundle install into a user-level cache (see
[ROADMAP.md](ROADMAP.md) §2).

---

## 2. Toolchain

- Dart SDK ≥ 3.11.0 (`pubspec.yaml`).
- Ruby 3.2.x (system or rbenv/asdf).
- Fastlane (currently via bundled Gemfile; brew formula will declare it).
- `dart pub get`, `dart test`, `dart compile exe bin/fastlane_cli.dart` are the
  primary commands.

There is no melos / workspace here anymore — it's a single self-contained
package.

---

## 3. Architecture (Dart side)

| Concern | Tool | Notes |
|---|---|---|
| TUI rendering | `nocterm` ^0.6.0 | terminal UI framework (component tree, theme) |
| Routing | `zenrouter_nocterm` (git fork) | Coordinator pattern from `definev/zenrouter` `feat/zenrouter_nocterm` |
| Args parsing | `args` ^2.7.0 | `--profile`, `--lang`, `--dry-run` |
| YAML | `yaml` ^3.1.3 | reading `profile.yaml` |
| Paths | `path` ^1.9.1 | runner/app dir resolution |
| Tests | `package:test` + `mocktail` (transitive via dev_deps) | |

No DI container — direct constructor injection (small surface).

### Profile model

`profile.yaml` (per app) is merged on top of `profile.base.yaml`
(bundled in this repo). Merge rules:
- `app:` — deep merge, app wins.
- `default_locale`, scalars — app wins if set.
- `supported_locales`, `shortcuts` — app wins (full replacement) if set.
- `categories`, `actions` — merged by `id`; app entries with same `id` replace
  base entry; new `id`s append.

The merge is implemented in `lib/src/services/profile_loader.dart`.

---

## 4. How the CLI runs a lane

1. `FastlaneCliLauncher.run(args)` parses `--profile`, loads + merges YAML,
   builds the route graph.
2. User picks an action (or short-circuits via `--action <id>`).
3. `CommandBuilder._buildFastlane` materializes a `CommandRequest`:
   - `executable: fastlane` (the system / brew-installed gem — NOT
     `bundle exec fastlane`; the slim `fastlane/Gemfile` is reserved for
     `storepilot_bridge.rb` and does not list fastlane itself)
   - `arguments: [<platform>, <lane>, key:value, ...]`
   - `workingDirectory: dirname(fastlaneRunnerPath)` (this repo's root)
   - `environment:` `FASTLANE_ROOT` (app's fastlane dir),
     `FASTLANE_APP_ROOT` (app root), `FASTLANE_CLI_FASTLANE_PATH`, plus any
     keys auto-forwarded from the app's `.env` files.

   storepilot_bridge invocations (when wired) keep the `bundle exec ruby
   storepilot_bridge.rb …` shape — that bundle is correct for the bridge.

   The same "no `bundle exec`" rule applies to **sub-lane delegation
   inside the Fastfile** via `sh("cd <runner> && fastlane <platform>
   <lane> …")` (e.g. `get_version_data` fanning out to
   `get_android_version_data` / `get_ios_version_data`). The brew formula
   declares `depends_on "fastlane"` so the gem is on PATH; prefixing
   `bundle exec` re-introduces the "Could not locate Gemfile" failure
   the Dart-side fix in v0.2.1 already removed for the top-level call.
4. `ProcessCommandExecutionService` spawns the process and streams logs into
   the TUI via `ansi_parsed_log_line`.

The `fastlane_runner_path` in a profile points at this repo's `fastlane/`
folder. After brew install lands, the CLI will auto-resolve it from
`Platform.resolvedExecutable` and the profile field becomes optional. Until
then, callers pass an absolute path.

---

## 5. Working rules (critical)

### 5.1 Fastlane summary log
Every user-facing lane and every storepilot_bridge command MUST end with a
coloured summary box via `FastlaneCliConfig.print_summary_box` /
`FastlaneCliConfig.summary_box`. Full procedure:
[skills/fastlane-summary-log/SKILL.md](skills/fastlane-summary-log/SKILL.md).
Cursor rule: [.cursor/rules/fastlane-logging.mdc](.cursor/rules/fastlane-logging.mdc).

### 5.2 No app-specific values
Nothing in this repo references a specific Flutter app (no app names,
no hardcoded bundle ids, no API keys). Everything app-specific is
supplied via the consumer's `profile.yaml` + environment variables
documented in `fastlane/ios/Fastfile` / `fastlane/android/Fastfile` headers.

If you find yourself wanting to hardcode a value, that value belongs in the
caller's profile or env, not here.

### 5.3 Credentials are env-driven
- iOS: `APP_STORE_CONNECT_API_KEY_JSON_PATH` (preferred) OR
  `APP_STORE_CONNECT_API_KEY_ID` + `_ISSUER_ID` + `_FILEPATH` (p8).
- Android: `GOOGLE_PLAY_JSON_KEY_PATH` (path to service account JSON).
- Bundle / package id: `IOS_APP_IDENTIFIER` / `ANDROID_PACKAGE_NAME` /
  `FASTLANE_APP_IDENTIFIER` OR via profile/option args.
- iOS Crashlytics symbols (only consumed when an action sets
  `upload_symbols: "true"` on the `test_flight` lane — see
  `fastlane/ios/Fastfile` `upload_dsyms` lane for the standalone handler).
  As of v0.8.0 this is **zero-config**: the `upload-symbols` binary and the
  `GoogleService-Info.plist` are auto-discovered at runtime by
  `FastlaneCliConfig.resolve_upload_symbols_script` /
  `resolve_google_service_info_plist`. A standard SwiftPM-Firebase app with
  `ios/flavors/<flavor>/GoogleService-Info.plist` (or
  `ios/Runner/GoogleService-Info.plist`) needs **no Crashlytics env vars**.
  Discovery precedence:
  - **upload-symbols**: explicit override → CocoaPods
    (`ios/Pods/FirebaseCrashlytics/upload-symbols`) → SwiftPM DerivedData
    glob (`~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/upload-symbols`,
    newest by mtime, then copied to a stable per-user cache at
    `~/Library/Caches/fastlane_cli/upload-symbols`) → vendored
    `ios/scripts/upload-symbols` → nil.
  - **GoogleService-Info.plist**: explicit override → flavor convention
    (`ios/flavors/<flavor>/GoogleService-Info.plist`) →
    `ios/Runner/GoogleService-Info.plist` → nil.
  `IOS_UPLOAD_SYMBOLS_SCRIPT` and `IOS_GOOGLE_SERVICE_INFO_PLIST` remain as
  **optional explicit overrides** for non-standard layouts — a user who set
  them keeps the exact same behaviour. Optional `IOS_DSYM_PATH` (default:
  `./build/ios/archive/Runner.xcarchive/dSYMs`). When discovery resolves
  nothing, `test_flight` soft-skips with a `"atlandı (upload-symbols
  bulunamadı)"` / `"atlandı (GoogleService-Info.plist bulunamadı)"` summary
  marker — never hard-fails the upload — while the standalone `upload_dsyms`
  lane hard-fails (`UI.user_error!`) since a no-op symbol upload is useless.
- Android Crashlytics symbols: the **R8/Kotlin mapping file** is uploaded
  automatically by the Firebase Crashlytics Gradle plugin during a release
  build (`flutter build appbundle --release`) — fastlane_cli does nothing
  for it. The **NDK native-symbol upload** IS wired (since v0.9.0): the
  `internal_testing` and `production` Android lanes, when an action sets
  `upload_symbols: "true"` (the SAME flag iOS `test_flight` uses), run
  `./android/gradlew -p android :app:uploadCrashlyticsSymbolFile<Flavor>Release`
  after the AAB build. The task name is built by
  `FastlaneCliConfig.crashlytics_symbol_task` from `resolve_flavor` (no
  flavor → `uploadCrashlyticsSymbolFileRelease`). The gradle shell-out is
  wrapped in `with_clean_subprocess_env`. **App-side prerequisite**: the
  consumer's `android/app/build.gradle.kts` must declare
  `firebaseCrashlytics { nativeSymbolUploadEnabled = true }` (inside the
  `android { buildTypes { release { ... } } }` block) for the Gradle task to
  exist. If it is absent — or the app has no native code — the gradle task
  errors; the lane catches that, soft-skips with a
  `"atlandı (uploadCrashlyticsSymbolFile task yok / nativeSymbolUploadEnabled
  kapalı)"` summary marker, and the AAB build+upload still succeeds (never
  hard-fails).
- Flutter Dart-obfuscation symbols: an `--obfuscate
  --split-debug-info=<dir>` build (driven by the `obfuscate` option — see
  `FastlaneCliConfig.flutter_build_flags`) writes Dart symbol mapping files
  into `<dir>` (the `split_debug_info` option, default `build/symbols`).
  Those must be uploaded to Crashlytics or Dart crash stack traces stay
  obfuscated. The **Dart symbol upload IS wired (since v0.11.0)**: the
  Android `internal_testing` / `production` lanes and the iOS `test_flight`
  lane call `FastlaneCliConfig.upload_flutter_symbols` after the build. It
  is **gated on BOTH `obfuscate` AND `upload_symbols` being truthy** (the
  same `upload_symbols` flag that drives dSYM / NDK upload) — if either is
  off it is a neutral no-op. On the happy path it runs
  `firebase crashlytics:symbols:upload --app=<id> <dir>` (wrapped in
  `with_clean_subprocess_env` + `in_app_root`). **Prerequisite**: the
  `firebase` CLI must be on PATH (`npm i -g firebase-tools` or
  `brew install firebase-cli`). The Firebase app id resolves from the
  `firebase_app_id` option → `FIREBASE_APP_ID_ANDROID` (android) /
  `FIREBASE_APP_ID_IOS` (ios) env var. It **soft-skips** (never
  hard-fails — mirrors the dSYM/NDK philosophy) when the `firebase` CLI is
  absent, the split-debug-info directory is missing/empty, no Firebase app
  id resolves, or the upload exits non-zero — surfacing a `"Dart symbols"`
  summary marker (`"yüklendi (flutter symbols)"`, `"atlandı (firebase CLI
  yok)"`, `"atlandı (split-debug-info dizini boş)"`, `"atlandı (Firebase
  app id yok)"`, `"atlandı (firebase symbols:upload başarısız)"`).

Never log secrets. The summary box helper auto-redacts known sensitive keys.
Redacted patterns (case-insensitive, value after `:` or `=` becomes `***`):
`password`, `api_key` / `api-key`, `secret`, `token`, `private_key`,
`json_key_data`, `client_secret`, `authorization`, `auth`. See
`SUMMARY_BOX_SECRET_KEY_PATTERNS` in `fastlane/common_helpers.rb`.

### 5.4 Vendor bundle stays out of git
`fastlane/vendor/` and `fastlane/.bundle/` are git-ignored. Local dev currently
uses `bundle install --path vendor/bundle`. The brew formula will pivot to a
user-cache location (`~/Library/Caches/fastlane_cli/bundle/<ruby>`). See
[ROADMAP.md](ROADMAP.md) §2.

### 5.5 Tests
- `dart test` from repo root runs the full suite.
- Mocking: `mocktail` (no `mockito`).
- Don't snapshot terminal output verbatim — assert structural properties
  (line count, presence of keywords, render-pass count).
- Always test success AND failure paths.

---

## 6. Distribution status

| Item | Status |
|---|---|
| Standalone repo extracted | ✅ |
| Public GitHub repo | ✅ `bthnkucuk/fastlane_cli` |
| LICENSE | ✅ MIT |
| Runner asset auto-resolve | ✅ Track A1 |
| Bundle cache + doctor first-run hook | ✅ Tracks B1+B2 |
| GH Actions release matrix | ✅ Track D1 |
| `homebrew-fastlane_cli` tap | ✅ `bthnkucuk/homebrew-fastlane_cli` |
| Public README | ✅ Track F1 |

Detailed task breakdown in [ROADMAP.md](ROADMAP.md).

---

## 6.1 Contributing — PR flow (mandatory)

`main` is protected. Direct pushes to `main` are blocked for the following
reasons:

- **Required status checks**: `Analyze + Test`, `Ruby specs (ruby 3.2)`,
  `Ruby specs (ruby 3.3)`, `Ruby specs (ruby 3.4)`.
- **No force pushes**, no deletions, required conversation resolution.
- `enforce_admins: false`, so the maintainer can admin-merge in an
  emergency — but every regular change goes through the same CI gate.

Every change — human or sub-agent — opens a PR:

```sh
git checkout -b <feature-branch>
# ... edits ...
git push -u origin <feature-branch>
gh pr create --base main --title "..." --body "..."
# wait for CI green, then:
gh pr merge --squash --delete-branch
```

Sub-agents working in `isolation: worktree` push their worktree branch to
origin and open a PR; the supervisor (Claude main) reviews + merges after
CI lands. The supervisor does NOT copy worktree files into the
maintainer's working tree — that path is closed by branch protection.

---

## 7. When in doubt

- Inspect the in-tree examples — `fastlane/Fastfile` `get_version_data` is the
  canonical summary-box reference; `storepilot_bridge.rb`
  `update_development_pubspec_version` is the bridge-style summary reference.
- The original monorepo guide for this package lives in the private source
  monorepo at commit `9d24baa7e^` (and was deleted in the extraction commit) —
  useful only for git archaeology.
