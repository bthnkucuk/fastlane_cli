---
name: fastlane-cli-layout
description: Resolve non-standard fastlane folder / `cli_profile.yaml` locations for fastlane_cli — distinguish the app's own `fastlane/` data folder from the bundled runner, pick the right knob (`root_path`, `fastlane_path`, `fastlane_runner_path`), and fix profile-discovery failures (walk-up, `--profile`, `$FASTLANE_CLI_PROFILE`). Triggers on: fastlane folder elsewhere, custom fastlane path, non-standard layout, monorepo, multi-app, profile not found, profile discovery, "Could not locate cli_profile.yaml", FASTLANE_CLI_PROFILE, --profile, walk-up, fastlane_path, fastlane_runner_path, root_path.
---

# fastlane_cli — non-standard layouts and profile discovery

Use this skill when the user has a layout that doesn't match the default
(`<app>/pubspec.yaml` + `<app>/fastlane/cli_profile.yaml`) — monorepos,
shared CI directories, renamed folders, or a "profile not found" error.

## Two `fastlane/` folders — do not confuse them

| #   | Folder                                | What's inside                                                                            | Who owns it          | Override knob              |
| --- | ------------------------------------- | ---------------------------------------------------------------------------------------- | -------------------- | -------------------------- |
| A   | The **app's own** `fastlane/` folder  | `cli_profile.yaml`, `metadata/`, `screenshots/`, `.env` — app-specific data              | Per consumer app     | `app.root_path` + `app.fastlane_path` |
| B   | The **bundled runner**                | `Fastfile`, `common_helpers.rb`, lane code — identical for every app, ships with the brew binary | fastlane_cli itself   | `app.fastlane_runner_path` (rarely needed) |

Most "fastlane folder is in a different place" questions are about A.
Question B only comes up when developing fastlane_cli itself or testing
against an unreleased runner build.

## Knob A.1 — `app.root_path`

Resolved relative to the directory that contains `cli_profile.yaml` (not
cwd). This is the Flutter project root — used to resolve every other
relative path in the profile, plus `$FASTLANE_APP_ROOT` for lanes.

| Where `cli_profile.yaml` lives        | What `root_path` should be |
| ------------------------------------- | -------------------------- |
| `<app>/fastlane/cli_profile.yaml`     | `..`                       |
| `<app>/cli_profile.yaml`              | `.`                        |
| `<app>/ci/fastlane/cli_profile.yaml`  | `../..`                    |
| Absolute path                         | Allowed, but discouraged — break on machine moves |

## Knob A.2 — `app.fastlane_path`

Default: `"fastlane"`, resolved relative to `root_path`. Determines where
the app's fastlane data lives — becomes `$FASTLANE_ROOT` for lanes, used to
find `metadata/`, `defaults/`, `.env`. Code path:
[`profile_loader.dart:47`](../../lib/src/services/profile_loader.dart) and
[`command_builder.dart:89`](../../lib/src/services/command_builder.dart).

| Scenario                                                | `fastlane_path` value           |
| ------------------------------------------------------- | ------------------------------- |
| Default — `<app>/fastlane/`                             | `fastlane` (or omit)            |
| Renamed — `<app>/ci/fastlane/`                          | `ci/fastlane`                   |
| Monorepo, shared elsewhere — `<repo>/tools/fastlane/<app>` | `../../tools/fastlane/<app>` (relative to `root_path`) |
| Absolute (shared CI mount)                              | `/opt/shared/fastlane/<app>`    |

## Knob B — `app.fastlane_runner_path` (advanced)

Default behaviour: [`RunnerResolver`](../../lib/src/services/runner_resolver.dart)
auto-finds the bundled runner by climbing up from `Platform.resolvedExecutable`,
looking for `share/fastlane_cli/fastlane/` (brew layout) or `fastlane/`
(source layout) — with `package:` URI fallback for `dart run` / `pub global
activate`.

Override only when:

- Developing core fastlane_cli and testing a new runner against a real app
  profile.
- Vendoring an unreleased build alongside an app.

```yaml
app:
  fastlane_runner_path: /abs/path/to/fastlane_cli/fastlane  # must contain Fastfile
```

Empty / missing → falls through to auto-resolution. The path must contain a
`Fastfile`; empty directories are not considered valid (intentional safety
check in `RunnerResolver._isFastlaneDir`).

## Profile discovery — `ProfileResolver` precedence

[`ProfileResolver`](../../lib/src/cli/profile_resolver.dart) decides which
`cli_profile.yaml` to load. Fixed precedence — first hit wins:

1. **`--profile <path>` flag.** Accepts a file or a directory. If a
   directory, looks inside for `cli_profile.yaml`, then
   `fastlane/cli_profile.yaml`.
2. **`$FASTLANE_CLI_PROFILE` env var.** Same file-or-dir semantics. Useful
   for shell sessions where you `cd` between apps.
3. **Walk-up discovery.** From cwd, climbs up to 8 levels looking for the
   first dir that contains both `pubspec.yaml` and
   `fastlane/cli_profile.yaml`. This is why `fastlane_cli` "just works"
   anywhere inside a standard-layout app.
4. **`./cli_profile.yaml` in cwd.** Final fallback.

When discovery happens via #1-dir, #2-dir, or #3, the CLI prints
`discovered: <abs path>` on stderr. Profile contents are never logged.

When none of the four resolve, the CLI raises
`ProfileResolutionException` with all four attempts listed and a remediation
block.

## Decision tree — pick the right fix

```
User has profile but CLI says "not found"
└─ Layout matches default (<app>/pubspec.yaml + <app>/fastlane/cli_profile.yaml)?
   ├─ YES → User isn't inside the app dir (or any subdir). cd into it,
   │        or pass --profile <abs path>, or export $FASTLANE_CLI_PROFILE.
   └─ NO  → Custom path. Choose:
            ├─ One-off / scripting / CI:  --profile <path>
            ├─ Daily dev in one shell:    export $FASTLANE_CLI_PROFILE
            └─ Permanent / many machines: rename or symlink so walk-up
                                          (#3) finds it; OR document the
                                          env var in onboarding.

User wants fastlane data folder NOT under <root>/fastlane/
└─ Edit cli_profile.yaml:
   - app.root_path:       relative path from cli_profile.yaml to app root
   - app.fastlane_path:   relative path from app root to fastlane data dir
   Verify with: fastlane_cli doctor --profile <path>

User wants to point at a different bundled runner
└─ app.fastlane_runner_path: <abs path containing Fastfile>
   (Almost certainly an "are you sure?" — most apps shouldn't touch this.)
```

## Concrete scenarios

### Monorepo with shared profile location

```
/repo/
  apps/aiNote/
    pubspec.yaml
    cli_profile.yaml             ← profile here, not under fastlane/
  tools/fastlane/aiNote/
    Fastfile-aside-data...       ← per-app fastlane data
```

```yaml
app:
  name: aiNote
  root_path: .
  fastlane_path: ../../tools/fastlane/aiNote
```

Profile won't be found by walk-up (no `<root>/fastlane/cli_profile.yaml`).
Use either:

```sh
fastlane_cli --profile /repo/apps/aiNote/cli_profile.yaml
# or
export FASTLANE_CLI_PROFILE=/repo/apps/aiNote
fastlane_cli   # dir form — looks for cli_profile.yaml then fastlane/cli_profile.yaml
```

### Multiple apps, one terminal session

Switch active app by re-exporting:

```sh
export FASTLANE_CLI_PROFILE=/repo/apps/aiNote
fastlane_cli run ios_test_flight        # aiNote

export FASTLANE_CLI_PROFILE=/repo/apps/other
fastlane_cli run android_internal_testing  # other
```

### CI — pin the profile, never depend on cwd

```yaml
# GitHub Actions snippet
- run: fastlane_cli run ios_internal_bump_deploy --profile ./apps/aiNote/fastlane/cli_profile.yaml
  working-directory: ${{ github.workspace }}
```

Don't rely on walk-up in CI — runners shuffle cwd and break it silently.

## Verification

After any layout change:

```sh
fastlane_cli list --json --profile <path>   # confirms profile loads + merges
fastlane_cli doctor --profile <path>        # confirms env / paths resolve
fastlane_cli run <some-id> --profile <path> --dry-run  # confirms FASTLANE_ROOT + FASTLANE_APP_ROOT
```

The dry-run output prints the materialized command including `environment`
— the `FASTLANE_ROOT` value should match the user's intended fastlane data
folder, and `FASTLANE_APP_ROOT` should match their Flutter project root.

## Do not

- Suggest `fastlane_runner_path` to a user who is just trying to relocate
  their own fastlane folder — that knob is for the *bundled runner*, a
  different concern. Use `fastlane_path` for app data.
- Set an absolute `root_path` unless the user explicitly wants
  machine-pinned behaviour — relative is portable.
- Edit fastlane_cli's own [`fastlane/cli_profile.base.yaml`](../../fastlane/cli_profile.base.yaml)
  for an app-specific layout — that file ships to every consumer.
- Recommend `--profile` flag on every invocation when the user could fix
  layout once and let walk-up handle the rest.
