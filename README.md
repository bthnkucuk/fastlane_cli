# fastlane_cli

![coverage](https://img.shields.io/badge/coverage-52.2%25-yellow)

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
brew install bthnkucuk/fastlane_cli/fastlane_cli
```

The Homebrew tap (`homebrew-fastlane_cli` under
[bthnkucuk](https://github.com/bthnkucuk)) is created once the first
tagged release ships — see [ROADMAP §E1](ROADMAP.md). Until then, use the
"from source" path below.

### From source (development)

```bash
git clone https://github.com/bthnkucuk/fastlane_cli
cd fastlane_cli
dart pub get
dart run bin/fastlane_cli.dart --profile /abs/path/to/cli_profile.yaml
```

Toolchain is FVM-pinned ([`.fvmrc`](.fvmrc)); install [direnv](https://direnv.net/) for project-scoped `dart` on PATH ([`.envrc`](.envrc) adds the FVM Dart SDK). Without direnv, prefix commands with `fvm dart …`.

Requirements:

- Dart SDK ≥ 3.11.0
- Ruby 3.2.x
- Fastlane (system gem or brew dep — see ROADMAP §0)

## Quickstart

Zero-config path — point `fastlane_cli` at a Flutter app that already has
`fastlane/cli_profile.yaml` and it discovers everything else:

```bash
cd /path/to/your-flutter-app
fastlane_cli                       # auto-discovers fastlane/cli_profile.yaml
fastlane_cli list                  # enumerate actions
fastlane_cli doctor                # validate env
fastlane_cli run get_version_data  # run a lane
```

On the first run from inside an app, the CLI prints one line to stderr like
`discovered: /abs/path/to/fastlane/cli_profile.yaml` so you can see where
the profile came from. The walk-up search climbs up to 8 levels looking for
the first directory containing both `pubspec.yaml` and
`fastlane/cli_profile.yaml`, so it works from anywhere inside the project
tree (e.g. `lib/src/foo/`).

The minimal `cli_profile.yaml`, placed at `<app>/fastlane/cli_profile.yaml`:

```yaml
app:
  name: my-app
  root_path: ..                      # project root, relative to this file
  fastlane_path: fastlane            # optional, defaults to "fastlane"
  default_locale: en                 # optional, "tr" by default
```

Everything else — shortcuts, categories, every iOS / Android / general
action — is inherited from the bundled
[`fastlane/cli_profile.base.yaml`](fastlane/cli_profile.base.yaml). You only
override entries by re-declaring an `action` / `category` with the same
`id`, or add new ones by giving them a fresh `id`. See
[Where things go](#where-things-go) for merge semantics.

Identifiers (bundle id, package name) are **not** in the YAML — they're
passed via env or per-action `command.options`. See
[Credentials](#credentials).

### `.env` auto-forwarding

When a lane runs, `fastlane_cli` automatically reads and forwards env values
from three documented locations (in ascending precedence — last wins among
files; the live shell environment always wins over any file):

1. `<app-root>/.env`
2. `<app-fastlane-dir>/.env`
3. `<app-fastlane-dir>/.env.<FASTLANE_FLAVOR>` (only when `FASTLANE_FLAVOR`
   is set in the shell)

`.env` syntax is intentionally narrow: `key=value` per line, `#` comments,
optional `export` prefix, single/double quotes stripped. `${VAR}`
interpolation is **not** supported.

This replaces the legacy `source fastlane/.env && fastlane_cli …`
incantation. Use `fastlane_cli run <id> --dry-run` to inspect the resolved
env (secret-looking keys are redacted to `***`).

### Explicit-profile path (scripting / CI)

```bash
fastlane_cli --profile /abs/path/to/cli_profile.yaml
fastlane_cli --profile /abs/path/to/some-app-dir   # or a directory
```

`--profile` accepts either a `cli_profile.yaml` file path or a directory
(in which case `cli_profile.yaml` and `fastlane/cli_profile.yaml` are
probed inside it).

CLI flags:

- `--profile <path>` — explicit profile file or app dir (optional;
  auto-discovered otherwise)
- `--lang tr|en` — override UI language
- `--dry-run` — print resolved commands + env without executing

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

### Fastlane plugins

The bundled runner ships a [`fastlane/Pluginfile`](fastlane/Pluginfile) that
declares the plugins lanes depend on (currently
`fastlane-plugin-firebase_app_distribution`, used by the `firebase_distribute`
lane). Lanes invoke `fastlane` directly from the system / brew-installed gem,
so plugins must be installed once into that gem's plugin path:

```bash
cd "$(brew --prefix fastlane_cli)/share/fastlane_cli/fastlane"
fastlane install_plugins
```

Run this once after `brew install bthnkucuk/fastlane_cli/fastlane_cli`. If you
do not use Firebase App Distribution you can ignore the
"plugins couldn't be loaded" warning — every other lane still runs.

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

> **Profile resolution.** Every subcommand that needs a profile looks it up in
> a fixed four-tier order (implemented in
> [`lib/src/cli/profile_resolver.dart`](lib/src/cli/profile_resolver.dart)):
>
> 1. `--profile <path>` (or `-p <path>`) on the command line. May be a
>    `cli_profile.yaml` file OR a directory (we probe `cli_profile.yaml`
>    then `fastlane/cli_profile.yaml` inside it).
> 2. `$FASTLANE_CLI_PROFILE` environment variable (same file-or-dir rules).
> 3. Walk-up app discovery: from the current working directory, climb up
>    to 8 levels looking for the first dir containing both `pubspec.yaml`
>    and `fastlane/cli_profile.yaml`.
> 4. `./cli_profile.yaml` in the current working directory.
>
> When discovery (#1-dir, #2-dir, or #3) resolves the profile, the CLI
> prints one line to stderr: `discovered: <abs-path>`.
>
> If none of the four points at an existing file, the command exits `66`
> (`EX_NOINPUT`) and prints every tried location plus a remediation hint.

### `fastlane_cli` (no subcommand) — TUI

```
fastlane_cli [--profile <path>] [--lang tr|en] [--dry-run] [--version]
```

Opens the categorized TUI (sidebar, slash palette, live logs, run tabs). With
no positional argument and no recognized subcommand, the binary delegates to
[`FastlaneCliLauncher`](lib/src/bootstrap/fastlane_cli_launcher.dart) (see
[`lib/src/cli/fastlane_cli_runner.dart`](lib/src/cli/fastlane_cli_runner.dart)).

| Flag | Description |
|---|---|
| `--profile`, `-p` | Path to `cli_profile.yaml`. Falls back to `$FASTLANE_CLI_PROFILE`, then `./cli_profile.yaml`. |
| `--lang tr\|en` | Override UI language (otherwise taken from the profile's `default_locale`). |
| `--dry-run` | Build resolved commands and stream them to the log without executing. |
| `--version`, `-v` | Print `fastlane_cli <version>` and exit 0. Short-circuits before profile resolution and TUI launch. |

```bash
fastlane_cli --profile /abs/path/to/cli_profile.yaml --lang en
```

### `fastlane_cli run <action-id>`

```
fastlane_cli run <action-id> [--profile <path>] [--option key=value ...] [--dry-run]
```

Run a single action by id, non-interactively. Streams the lane's stdout/stderr
as plain text and propagates the lane's exit code. Unknown ids exit `64` with
a pointer to `fastlane_cli list`.

| Flag | Description |
|---|---|
| `--profile`, `-p` | Profile path (standard three-tier resolution). |
| `--option`, `-o` `key=value` | Override or add a single command option. Repeatable. Merged on top of the action's `command.options`. Only `fastlane`-type commands accept options. |
| `--dry-run` | Print the resolved command without spawning a process. |

```bash
fastlane_cli run android_internal_testing --option track=alpha --option skip_upload_metadata=true
```

### `fastlane_cli list`

```
fastlane_cli list [--profile <path>] [--category <id>] [--json]
```

Enumerate every action visible in the merged profile (base + per-app).

| Flag | Description |
|---|---|
| `--profile`, `-p` | Profile path (standard three-tier resolution). |
| `--category`, `-c` `<id>` | Filter to a single category id. |
| `--json` | Emit a JSON array instead of `id\t[category]\ttitle` text. |

JSON shape (one object per action):

```json
[
  {
    "id": "ios_test_flight",
    "title": "iOS — TestFlight build & upload",
    "description": "Builds the .ipa and uploads it to TestFlight.",
    "category": "ios_release"
  }
]
```

```bash
fastlane_cli list --category ios_release --json
```

### `fastlane_cli init`

```
fastlane_cli init [--app-name <name>] [--platform ios|android|both] [--force]
```

Scaffold a minimal `cli_profile.yaml` in the current directory. Writes inline
comments pointing at the credential env vars for the chosen platform. Exits
`73` (`EX_CANTCREAT`) if `cli_profile.yaml` already exists and `--force` was
not passed.

| Flag | Default | Description |
|---|---|---|
| `--app-name` | `my-app` | Value written into `app.name` in the scaffold. |
| `--platform` | `both` | Which credential-hint comment block to keep. One of `ios`, `android`, `both`. |
| `--force` | `false` | Overwrite an existing `cli_profile.yaml`. |

```bash
fastlane_cli init --app-name my-app --platform ios
```

### `fastlane_cli doctor`

```
fastlane_cli doctor [--profile <path>]
```

Runs environment checks for the active profile: locates and parses the
profile, then validates the surrounding toolchain (Ruby version, Fastlane
version, bundle cache presence, declared credentials reachable). Implementation
of the full check matrix is in progress (Track B2); the user-facing contract
is stable:

- Exit `0` — all required checks passed. Warnings (non-fatal advisories) may
  still print to stdout.
- Exit `1` — one or more required checks failed; lane execution would be
  unsafe.
- Exit `66` — could not locate `cli_profile.yaml` (same resolution rules as
  every other subcommand).

| Flag | Description |
|---|---|
| `--profile`, `-p` | Profile path (standard three-tier resolution). |

```bash
fastlane_cli doctor --profile ./cli_profile.yaml
```

### `fastlane_cli skills install`

```
fastlane_cli skills install [--global|--project] [--force] [--dry-run]
```

Copy the bundled [`skills/`](skills/) directory into a Claude Code skills
location. `--global` and `--project` are mutually exclusive; `--project`
(`<cwd>/.claude/skills/`) is the default. Without `--force`, existing skill
directories are left untouched (idempotent).

| Flag | Description |
|---|---|
| `--project` | Install into `<cwd>/.claude/skills/`. Default. |
| `--global` | Install into `~/.claude/skills/` instead. |
| `--force` | Overwrite existing skill directories of the same name. |
| `--dry-run` | List what would be copied; do not write anything. |

```bash
fastlane_cli skills install --project
fastlane_cli skills install --global --force
```

### `fastlane_cli completion <bash|zsh|fish>`

```
fastlane_cli completion <bash|zsh|fish> [--profile <path>]
```

Emit a shell completion script to stdout. Subcommand names are always
included; action ids are appended when a profile is discoverable (so
`fastlane_cli run <TAB>` completes them). A missing or malformed profile is
not fatal — completion still works for the static subcommand list.

| Flag | Description |
|---|---|
| `--profile`, `-p` | Profile path used to enumerate action ids. Optional. |

Install (per shell):

```bash
# bash — add to ~/.bashrc
source <(fastlane_cli completion bash)

# zsh — add to ~/.zshrc
source <(fastlane_cli completion zsh)

# fish — write into the completions directory
fastlane_cli completion fish > ~/.config/fish/completions/fastlane_cli.fish
```

For IDE-style inline ghost-text + dropdown completions in **Amazon Q Developer
CLI for command line** (formerly Fig) and **Kiro CLI**, see
[`dist/amazon-q-spec/`](dist/amazon-q-spec/) — the same subcommand/flag tree,
mirrored upstream at `withfig/autocomplete/src/fastlane_cli.ts`.

## Skills

The CLI ships a set of bundled **Claude Code skills** — natural-language
workflows that wrap the subcommands above. Each skill lives in its own
directory under [`skills/`](skills/) with a `SKILL.md` whose frontmatter
declares the trigger keywords. Consumers drop the tree into their Claude
config (project-local or global) and Claude Code matches user requests like
"ship a TestFlight" or "what version are we on?" to the right skill, which in
turn invokes `fastlane_cli`.

| Skill | One-liner |
|---|---|
| [`fastlane-cli-setup`](skills/fastlane-cli-setup/SKILL.md) | Scaffold a per-app `cli_profile.yaml` and the credential env vars needed to drive fastlane_cli in a fresh Flutter project. |
| [`fastlane-cli-run`](skills/fastlane-cli-run/SKILL.md) | Translate a natural-language request into a concrete `fastlane_cli run <action-id>` invocation. |
| [`fastlane-version-bump`](skills/fastlane-version-bump/SKILL.md) | Inspect or bump the Flutter app's pubspec `version: X.Y.Z+N` and reconcile it with the Android Play track and the App Store Connect build number. |
| [`fastlane-metadata-sync`](skills/fastlane-metadata-sync/SKILL.md) | Pull or push store metadata (titles, descriptions, release notes, screenshots, App Privacy) between the local `fastlane/metadata/` tree and the App Store / Play Console. |
| [`fastlane-testflight`](skills/fastlane-testflight/SKILL.md) | End-to-end iOS TestFlight release flow via fastlane_cli — credential prerequisites, version handling, and the canonical action ids. |
| [`fastlane-play-internal`](skills/fastlane-play-internal/SKILL.md) | End-to-end Android Play Console internal-track release flow via fastlane_cli — service account, version handling, and the canonical action ids. |
| [`fastlane-doctor`](skills/fastlane-doctor/SKILL.md) | Diagnose fastlane_cli env/credential/toolchain issues before invoking a lane. |
| [`fastlane-summary-log`](skills/fastlane-summary-log/SKILL.md) | Add a coloured, box-bordered "human summary" log block to fastlane lanes and storepilot_bridge commands. |

How to install:

```bash
fastlane_cli skills install --project   # repo-local: <cwd>/.claude/skills/
fastlane_cli skills install --global    # user-wide:  ~/.claude/skills/
```

See [`skills/README.md`](skills/README.md) for the canonical index and
authoring rules.
