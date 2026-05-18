---
name: fastlane-cli-setup
description: Scaffold a per-app `cli_profile.yaml` and the credential env vars needed to drive fastlane_cli in a fresh Flutter project. Triggers on: setup, scaffold, init, initialize, new project, cli_profile.yaml, configure fastlane_cli, onboard, bootstrap, getting started.
---

# fastlane_cli — first-time setup

Use this skill when the user has a Flutter project that does **not** yet have a
`cli_profile.yaml` and wants to start driving lanes through `fastlane_cli`.

Goal: produce a minimal, working `cli_profile.yaml` at the project root (next
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
   `cli_profile.yaml`.

Do **not** invent values. If unknown, leave the field commented out with a
TODO marker.

## Step 2 — Generate `cli_profile.yaml`

Prefer the future `fastlane_cli init` subcommand (post-1.0, see
[ROADMAP.md](../../ROADMAP.md) §7). When that is unavailable, write the file
directly with this minimal template (omit blocks for platforms the user
isn't shipping):

```yaml
# cli_profile.yaml — merged on top of fastlane_cli's bundled cli_profile.base.yaml.
# Only declare app-specific fields here.

app:
  name: <App display name>
  root_path: .                # project root, relative to this file
  ios:
    app_identifier: <com.example.app>
  android:
    package_name: <com.example.app>

# default_locale: en           # uncomment to override base (base default: tr)
# supported_locales: [en, tr]  # uncomment to fully replace base list
# shortcuts:                   # uncomment to fully replace base shortcut list
#   - internal_test
#   - ios_test_flight
#   - android_internal_testing

# Action / category overrides: declare by id to replace the base entry; new
# ids append. See fastlane/cli_profile.base.yaml in fastlane_cli for the
# canonical list of base actions.
# actions:
#   - id: <id>
#     ...
```

Notes:
- `fastlane_runner_path:` is intentionally **not** in the template. Until
  [ROADMAP.md](../../ROADMAP.md) §1 lands it is required and must point at
  an absolute path to fastlane_cli's `fastlane/` folder. After that ships
  the CLI auto-resolves it.
- Merge rules (recap):
  - `app:` deep-merges (app wins per key).
  - Scalars (`default_locale`, ...) — app wins if set.
  - `supported_locales` / `shortcuts` — full replacement when set.
  - `categories` / `actions` — merged by `id`.

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

Optional identifier override (otherwise read from `cli_profile.yaml`):

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

### Optional, both platforms

```sh
export FASTLANE_FLAVOR="<flavor>"       # only if the project uses flavors
export FASTLANE_PUBSPEC_PATH="/abs/path/to/pubspec.yaml"  # only if non-standard
```

## Step 4 — Verify

From inside the Flutter app's root directory (or any subdirectory of it),
no flags required — `fastlane_cli` walks up looking for the dir that
contains both `pubspec.yaml` and `fastlane/cli_profile.yaml`:

```sh
cd /path/to/your-flutter-app
fastlane_cli doctor      # validate env (see fastlane-doctor skill)
fastlane_cli list --json # confirm the profile loads
```

The CLI prints `discovered: /abs/path/to/fastlane/cli_profile.yaml` on
stderr so the user sees which profile was picked up. `.env` files placed
at `<app>/fastlane/.env`, `<app>/.env`, and `<app>/fastlane/.env.<flavor>`
(when `FASTLANE_FLAVOR` is set) are auto-forwarded into the lane process —
no `source fastlane/.env` needed.

Explicit-profile path still works for scripting / CI:

```sh
fastlane_cli doctor --profile ./fastlane/cli_profile.yaml
fastlane_cli list --json --profile ./fastlane/cli_profile.yaml
```

If both succeed, the user is ready. Hand off to `fastlane-cli-run` for "how do
I trigger a lane" requests, or to `fastlane-testflight` /
`fastlane-play-internal` for first-release flows.

## Do not

- Hardcode app names, bundle ids, or any API keys into this repo.
- Add a `fastlane_runner_path` to the profile unless the user is on
  pre-ROADMAP §1 builds and explicitly needs it.
- Commit `.env` / API key JSON / `.p8` files to git.
