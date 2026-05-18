# fastlane_cli

A terminal-first Fastlane assistant for Flutter projects. Drop a
`cli_profile.yaml` next to your own `fastlane/` folder and `fastlane_cli`
exposes your iOS + Android lanes through a categorized TUI (sidebar, slash
palette, live logs, run tabs) — no Ruby bootstrap, no per-app glue scripts.
Intended for any Flutter app that already has, or wants to add, Fastlane
lanes for TestFlight / App Store / Play Console.

> **Note on `flutter clean` in lanes:** the shared `internal_test` lane (and any caller passing `run_clean: true`) used to invoke `flutter clean` directly, which takes **5+ minutes** in Firebase-via-SwiftPM Flutter apps because `xcodebuild clean` re-resolves the SwiftPM package graph per scheme. As of [Fastfile L228](fastlane/Fastfile#L228), that step is replaced with a targeted `rm -rf` of `build`, `.dart_tool`, and the iOS ephemeral/Flutter-framework artifacts — same end state, ~5 seconds instead of ~322 seconds. `Podfile.lock` is intentionally left intact. Tracking: [flutter#173940](https://github.com/flutter/flutter/issues/173940), [flutter#180758](https://github.com/flutter/flutter/issues/180758).

## Install

### Homebrew (recommended, once published)

```bash
brew install <owner>/fastlane_cli/fastlane_cli
```

The `<owner>` placeholder is intentional — the GitHub owner / tap is still
being chosen. See [ROADMAP §0](ROADMAP.md#0-pending-decisions-block-work) and
[Track §4 — Homebrew tap](ROADMAP.md#4-homebrew-tap--small-mechanical-after-3).

### From source (development)

```bash
git clone <repo-url> fastlane_cli
cd fastlane_cli
dart pub get
dart run bin/fastlane_cli.dart --profile /abs/path/to/cli_profile.yaml
```

Requirements:

- Dart SDK ≥ 3.11.0
- Ruby 3.2.x
- Fastlane (system gem or brew dep — see ROADMAP §0)

## Quickstart

Create a `cli_profile.yaml` somewhere convenient (typically inside your
Flutter project, next to its own `fastlane/` folder):

```yaml
app:
  name: my-app
  root_path: /abs/path/to/flutter/project
  fastlane_path: fastlane            # optional, defaults to "fastlane"
  fastlane_runner_path: /abs/path/to/fastlane_cli/fastlane  # required until runner auto-resolve lands (ROADMAP §1)
  default_locale: en                 # optional, "tr" by default
```

That's the minimum. Everything else — shortcuts, categories, every iOS /
Android / general action — is inherited from the bundled
[`fastlane/cli_profile.base.yaml`](fastlane/cli_profile.base.yaml). You only
override entries by re-declaring an `action` / `category` with the same `id`,
or add new ones by giving them a fresh `id`. See [Where things go](#where-things-go)
for merge semantics.

Identifiers (bundle id, package name) are **not** in the YAML — they're
passed via env or per-action `command.options`. See
[Credentials](#credentials).

Run it:

```bash
dart run bin/fastlane_cli.dart --profile /abs/path/to/cli_profile.yaml
```

CLI flags:

- `--profile <path>` — profile YAML path (required)
- `--lang tr|en` — override UI language
- `--dry-run` — print resolved commands without executing

## Credentials

All credentials are env-driven. Nothing is read from the profile YAML.

| Platform | Variable | Purpose |
|---|---|---|
| iOS | `APP_STORE_CONNECT_API_KEY_JSON_PATH` | Path to App Store Connect API key JSON (preferred) |
| iOS | `APP_STORE_CONNECT_API_KEY_ID` | Key ID (used with `_ISSUER_ID` + `_FILEPATH` if no JSON path) |
| iOS | `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Issuer ID |
| iOS | `APP_STORE_CONNECT_API_KEY_FILEPATH` | Path to the `.p8` key file |
| iOS | `IOS_APP_IDENTIFIER` or `FASTLANE_IOS_APP_IDENTIFIER` | iOS bundle id (e.g. `com.example.app`) |
| Android | `GOOGLE_PLAY_JSON_KEY_PATH` | Path to Play Console service-account JSON |
| Android | `ANDROID_PACKAGE_NAME` or `FASTLANE_ANDROID_APP_IDENTIFIER` | Android package name (e.g. `com.example.app`) |
| Shared | `FASTLANE_APP_IDENTIFIER` / `APP_IDENTIFIER` | Used when iOS + Android share an identifier |

Either pick the JSON-path strategy on iOS (`APP_STORE_CONNECT_API_KEY_JSON_PATH`)
or the three-piece p8 strategy (`_ID` + `_ISSUER_ID` + `_FILEPATH`). Don't mix.

Identifiers can also be passed as per-action `command.options` in the profile
(e.g. `app_identifier: com.example.app`) — env vars are usually the cleaner
choice.

Lane headers in [`fastlane/ios/Fastfile`](fastlane/ios/Fastfile) and
[`fastlane/android/Fastfile`](fastlane/android/Fastfile) document any
lane-specific extras.

## First run

A `fastlane_cli doctor` subcommand is planned — it will install the bundle
into a user cache and validate Ruby / Fastlane / the chosen credentials. See
[ROADMAP §2](ROADMAP.md#2-vendor-bundle--user-cache--medium-ux-shaping). For
now, manual setup:

```bash
cd /path/to/fastlane_cli/fastlane
bundle install --path vendor/bundle
```

This populates `fastlane/vendor/bundle/` (git-ignored, ~111 MB). Subsequent
runs reuse it.

**Coming soon** (Wave 3): `fastlane_cli doctor` and automatic first-run bundle
installation into `~/Library/Caches/fastlane_cli/bundle/<ruby-abi>`.

## Where things go

The CLI loads your `cli_profile.yaml` and merges it on top of the bundled
[`fastlane/cli_profile.base.yaml`](fastlane/cli_profile.base.yaml). Merge
rules (canonical implementation:
[`lib/src/services/profile_loader.dart`](lib/src/services/profile_loader.dart)):

- `app:` — deep merge; app values win per key.
- `default_locale` and other scalars — app wins if set.
- `supported_locales`, `shortcuts` — app fully replaces base when set.
- `categories`, `actions` — merged by `id`. App entries with the same `id`
  replace the base entry; new `id`s append.

The bundled runner lives at `<install-prefix>/share/fastlane_cli/fastlane/`
once installed via brew. During development, point `app.fastlane_runner_path`
at this repo's `fastlane/` directory. Runner auto-resolution is tracked in
[ROADMAP §1](ROADMAP.md#1-runner-asset-auto-resolve-small-mostly-mechanical).

## Subcommand reference

Coming in v0.1 — see [ROADMAP Track A2](ROADMAP.md).

## Skills

Coming in v0.1 — see [ROADMAP Track C](ROADMAP.md).
