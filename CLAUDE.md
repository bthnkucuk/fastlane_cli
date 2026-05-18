# CLAUDE.md

Guidance for Claude Code / Cursor working inside the **fastlane_cli** repo.

This is a standalone Dart CLI that drives Fastlane lanes for any Flutter app
through a categorized, terminal-first UI. It was extracted from a private
monorepo at commit `9d24baa7e` of that repo (see [ROADMAP.md](ROADMAP.md)).

End goal: ship as a Homebrew-installable CLI (`brew install fastlane_cli`) so
any Flutter project can drop a `cli_profile.yaml` next to its own `fastlane/`
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
  cli_profile.base.yaml # Shared shortcuts/categories/actions merged into every app profile
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
| YAML | `yaml` ^3.1.3 | reading `cli_profile.yaml` |
| Paths | `path` ^1.9.1 | runner/app dir resolution |
| Tests | `package:test` + `mocktail` (transitive via dev_deps) | |

No DI container — direct constructor injection (small surface).

### Profile model

`cli_profile.yaml` (per app) is merged on top of `cli_profile.base.yaml`
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
   - `executable: bundle`
   - `arguments: [exec, fastlane, <platform>, <lane>, key:value, ...]`
   - `workingDirectory: dirname(fastlaneRunnerPath)` (this repo's root)
   - `environment:` `BUNDLE_GEMFILE`, `FASTLANE_ROOT` (app's fastlane dir),
     `FASTLANE_APP_ROOT` (app root), `FASTLANE_CLI_FASTLANE_PATH`.
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
[.claude/skills/fastlane-summary-log/SKILL.md](.claude/skills/fastlane-summary-log/SKILL.md).
Cursor rule: [.cursor/rules/fastlane-logging.mdc](.cursor/rules/fastlane-logging.mdc).

### 5.2 No app-specific values
Nothing in this repo references a specific Flutter app (no app names,
no hardcoded bundle ids, no API keys). Everything app-specific is
supplied via the consumer's `cli_profile.yaml` + environment variables
documented in `fastlane/ios/Fastfile` / `fastlane/android/Fastfile` headers.

If you find yourself wanting to hardcode a value, that value belongs in the
caller's profile or env, not here.

### 5.3 Credentials are env-driven
- iOS: `APP_STORE_CONNECT_API_KEY_JSON_PATH` (preferred) OR
  `APP_STORE_CONNECT_API_KEY_ID` + `_ISSUER_ID` + `_FILEPATH` (p8).
- Android: `GOOGLE_PLAY_JSON_KEY_PATH` (path to service account JSON).
- Bundle / package id: `IOS_APP_IDENTIFIER` / `ANDROID_PACKAGE_NAME` /
  `FASTLANE_APP_IDENTIFIER` OR via profile/option args.

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
| `git init` + local `main` | ✅ |
| GitHub remote | ⏳ user will create |
| LICENSE | ⏳ pending (Apache-2.0 vs MIT) |
| Runner asset auto-resolve | ⏳ pending — see ROADMAP §1 |
| Vendor bundle → user cache | ⏳ pending — see ROADMAP §2 |
| GH Actions release matrix | ⏳ pending — see ROADMAP §3 |
| `homebrew-fastlane_cli` tap | ⏳ pending — see ROADMAP §4 |
| Public README | ⏳ pending — see ROADMAP §5 |

Detailed task breakdown in [ROADMAP.md](ROADMAP.md).

---

## 7. When in doubt

- Inspect the in-tree examples — `fastlane/Fastfile` `get_version_data` is the
  canonical summary-box reference; `storepilot_bridge.rb`
  `update_development_pubspec_version` is the bridge-style summary reference.
- The original monorepo guide for this package lives in the private source
  monorepo at commit `9d24baa7e^` (and was deleted in the extraction commit) —
  useful only for git archaeology.
