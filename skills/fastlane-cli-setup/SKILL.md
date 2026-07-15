---
name: fastlane-cli-setup
description: Scaffold a per-app `profile.yaml` and the credential env vars needed to drive fastlane_cli in a fresh Flutter project. Triggers on: setup, scaffold, init, initialize, new project, profile.yaml, configure fastlane_cli, onboard, bootstrap, getting started.
---

# fastlane_cli — first-time setup

Use this skill when the user has a Flutter project that does **not** yet have a
`profile.yaml` and wants to start driving lanes through `fastlane_cli`.

Goal: produce a minimal, working `profile.yaml` at the project root (next
to `pubspec.yaml`) and confirm the credential env vars for the platforms they
plan to ship.

## Step 1 — Confirm the project shape

Ask (or detect from the filesystem) before generating anything:

1. **App display name** — used only as the YAML `app.name` label (not the
   bundle id).
2. **Platforms** — iOS, Android, or both.
3. **iOS bundle identifier** — e.g. `com.example.app` (only if iOS).
4. **Android package name** — e.g. `com.example.app` (only if Android).
5. **Flavors** — single flavor or multiple (most projects: none).
6. **Project root** — absolute path. The profile lives here as
   `profile.yaml`.

Do **not** invent values. If unknown, leave the field commented out with a
TODO marker.

## Step 2 — Generate `profile.yaml`

Prefer the `fastlane_cli init` subcommand — it scaffolds a `profile.yaml` in
the current directory:

```sh
cd /path/to/your-flutter-app
fastlane_cli init --app-name MyApp --platform both   # ios | android | both
# already have a profile.yaml? overwrite it explicitly:
fastlane_cli init --app-name MyApp --force
```

`init` writes a minimal `profile.yaml` (with `app.name`, `app.root_path`,
`app.fastlane_path`, `default_locale`, and commented credential hints for the
chosen platform) next to `pubspec.yaml`. It refuses to clobber an existing
`profile.yaml` unless `--force` is passed (exit code 73 otherwise). Then edit
`app.root_path` to point at the Flutter project root and add the optional
`package_name` / `bundle_id` identity keys (see below).

When you need finer control than `init` provides, write the file directly
with this template (omit blocks for platforms the user isn't shipping):

```yaml
# profile.yaml — merged on top of fastlane_cli's bundled profile.base.yaml.
# Only declare app-specific fields here.

app:
  name: MyApp
  root_path: .                  # project root, relative to this file
  package_name: com.example.myapp  # Android applicationId (optional)
  bundle_id:    com.example.myapp  # iOS bundle id          (optional)

# App identity (package_name / bundle_id) belongs in the `app:` block, NOT in
# default_options — default_options is for build/lane options. Both keys are
# optional. They are the LOWEST-precedence option layer: a value also set in
# default_options, a per-action command.options block, or a --option flag wins.

# default_locale: en           # uncomment to override base (base default: tr)
# supported_locales: [en, tr]  # uncomment to fully replace base list
# shortcuts:                   # uncomment to fully replace base shortcut list
#   - internal_test
#   - ios_test_flight
#   - android_internal_testing

# default_options: applied underneath EVERY lane's command.options. Best knob
# for a per-flavor profile — e.g. a multi-flavor app whose entry point is
# lib/main_<flavor>.dart. Per-action options and `--option` still win on top.
# default_options:
#   flavor: <flavor>
#   target: lib/main_<flavor>.dart

# Action / category overrides: declare by id to replace the base entry; new
# ids append. Only needed when ONE lane needs a value different from the
# profile-wide default_options. See fastlane/profile.base.yaml in
# fastlane_cli for the canonical list of base actions.
# actions:
#   - id: <id>
#     ...
```

For a multi-flavor app, the cleanest layout is one profile **per flavor**,
each just `app:` + `default_options:` — no `actions:` block at all. The base
profile supplies every lane; `default_options` pins `flavor` + `target` on all
of them at once.

Notes:
- `fastlane_runner_path:` is intentionally **not** in the template. The CLI
  auto-resolves the bundled runner from the installed `fastlane_cli` binary
  (`RunnerResolver`). Only set `app.fastlane_runner_path` to override that —
  e.g. when developing fastlane_cli itself against a real app profile (see
  `fastlane-cli-layout`).
- Merge rules (recap):
  - `app:` deep-merges (app wins per key).
  - Scalars (`default_locale`, ...) — app wins if set.
  - `supported_locales` / `shortcuts` — full replacement when set.
  - `categories` / `actions` — merged by `id`.
  - `default_options` — deep-merges (app wins per key), then folds underneath
    every `fastlane`-action's `command.options` (per-action keys win).
- Option precedence (lowest → highest):
  `app:` block identity (`package_name` / `bundle_id`) < `default_options` <
  per-action `command.options` < `--option` CLI flag.

## Step 3 — Credential env vars

Pick a shell-init location the user actually sources (`~/.zshrc`,
`~/.config/fish/config.fish`, a per-project `.envrc` for `direnv`, or a CI
secret store). Do **not** commit secrets to the repo.

### iOS (App Store Connect)

Preferred — single JSON key file:

```sh
export APP_STORE_CONNECT_API_KEY_JSON_PATH="/abs/path/to/api_key.json"
```

Alternative — id + issuer + p8 triple:

```sh
export APP_STORE_CONNECT_API_KEY_ID="ABC123"
export APP_STORE_CONNECT_API_KEY_ISSUER_ID="xxxx-xxxx-xxxx-xxxx"
export APP_STORE_CONNECT_API_KEY_FILEPATH="/abs/path/AuthKey_ABC123.p8"
```

Optional identifier override (otherwise read from `profile.yaml`):

```sh
export IOS_APP_IDENTIFIER="com.example.app"
# or the shared shortcut, used when iOS and Android ids match:
export FASTLANE_APP_IDENTIFIER="com.example.app"
```

### Android (Google Play)

```sh
export GOOGLE_PLAY_JSON_KEY_PATH="/abs/path/to/play-service-account.json"
```

Optional identifier override:

```sh
export ANDROID_PACKAGE_NAME="com.example.app"
# or the shared shortcut:
export FASTLANE_APP_IDENTIFIER="com.example.app"
```

Optional — Play Console "Set up your app" lanes (`android_store_setup`,
`android_update_app_details`, `android_upload_data_safety`; see
`fastlane-metadata-sync`). Each also resolves from a metadata-root file
(`contactEmail.txt` etc.) when unset:

```sh
export ANDROID_CONTACT_EMAIL="support@example.com"    # Play Console contact email
export ANDROID_CONTACT_PHONE="+10000000000"           # Play Console contact phone
export ANDROID_CONTACT_WEBSITE="https://example.com"  # Play Console contact website
export ANDROID_DEFAULT_LANGUAGE="en-US"               # listing default language (BCP-47)
export ANDROID_DATA_SAFETY_CSV_PATH="/abs/path/data_safety.csv"  # Data safety CSV override
```

### Optional, both platforms

```sh
export FASTLANE_FLAVOR="<flavor>"       # only if the project uses flavors
export FASTLANE_PUBSPEC_PATH="/abs/path/to/pubspec.yaml"  # only if non-standard
```

## Step 4 — Verify

From inside the Flutter app's root directory (or any subdirectory of it),
no flags required — `fastlane_cli` walks up looking for the dir that
contains both `pubspec.yaml` and `fastlane/profile.yaml`:

```sh
cd /path/to/your-flutter-app
fastlane_cli doctor      # validate env (see fastlane-doctor skill)
fastlane_cli list --json # confirm the profile loads
```

The CLI prints `discovered: /abs/path/to/fastlane/profile.yaml` on
stderr so the user sees which profile was picked up. `.env` files placed
at `<app>/fastlane/.env`, `<app>/.env`, and `<app>/fastlane/.env.<flavor>`
(when `FASTLANE_FLAVOR` is set) are auto-forwarded into the lane process —
no `source fastlane/.env` needed.

Explicit-profile path still works for scripting / CI:

```sh
fastlane_cli doctor --profile ./fastlane/profile.yaml
fastlane_cli list --json --profile ./fastlane/profile.yaml
```

`fastlane_cli list` emits a flat JSON array of `{id, title, description,
category}` objects with `--json`, or a plain `id  [category]  title` listing
without it. Use `--category <id>` to filter.

## Step 5 — Optional terminal niceties

Shell completion — covers the static subcommands, and `run <TAB>` completes
action ids when a profile is discoverable:

```sh
fastlane_cli completion zsh  >> ~/.zshrc           # or: bash | fish
fastlane_cli completion bash >> ~/.bashrc
fastlane_cli completion fish > ~/.config/fish/completions/fastlane_cli.fish
```

Install the bundled Claude Code / Cursor skills into the project (or globally)
so an assistant working in the repo has this guidance on hand:

```sh
fastlane_cli skills install            # → <cwd>/.claude/skills/ (project)
fastlane_cli skills install --global   # → ~/.claude/skills/
fastlane_cli skills install --dry-run  # preview without writing
fastlane_cli skills install --force    # overwrite existing skill dirs
```

If all of the above succeed, the user is ready. Hand off to `fastlane-cli-run`
for "how do I trigger a lane" requests, or to `fastlane-testflight` /
`fastlane-play-internal` for first-release flows.

## Do not

- Hardcode app names, bundle ids, or any API keys into this repo.
- Add a `fastlane_runner_path` to the profile — the CLI auto-resolves the
  bundled runner. Only set it to point at a non-default runner build.
- Commit `.env` / API key JSON / `.p8` files to git.
