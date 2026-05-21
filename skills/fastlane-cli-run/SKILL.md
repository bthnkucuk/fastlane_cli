---
name: fastlane-cli-run
description: Translate a natural-language request ("ship to internal", "build a TestFlight", "what's the current version") into a concrete `fastlane_cli run <action-id>` invocation. Triggers on: run, ship, deploy, release, build and upload, fire the lane, trigger, kick off, dispatch, "I want to ...", what action.
---

# fastlane_cli — run an action

Use this skill when the user describes an outcome (in plain English/Turkish)
and you must pick the correct `fastlane_cli` action to invoke.

**Critical rule**: do NOT rely on a hardcoded list of action ids. Action ids
are profile-dependent — the user's `profile.yaml` may add, replace, or
remove entries on top of fastlane_cli's bundled `profile.base.yaml`.
Always discover the active set at runtime.

## Step 1 — Discover available actions

Call the JSON listing subcommand. The `--profile` flag is **optional** — when
omitted, the CLI resolves the active profile by walk-up discovery (see
`fastlane-cli-layout`):

```sh
fastlane_cli list --json                              # auto-resolve profile
fastlane_cli list --json --profile <path>             # explicit profile
fastlane_cli list --json --category ios               # filter to one category
```

`fastlane_cli list --json` emits a **flat JSON array**, one object per
resolved action in profile order (titles/descriptions already localized to
the profile's `default_locale`):

```json
[
  {
    "id": "ios_test_flight",
    "title": "iOS TestFlight",
    "description": "TestFlight upload lane",
    "category": "ios"
  }
]
```

Without `--json` the same listing prints as plain text — one `id\t[category]\ttitle`
line per action, with the description indented underneath:

```sh
fastlane_cli list                       # human-readable
fastlane_cli list --category android    # one category only
```

Parsing approach:

1. Build a flat `id → action` map from the array.
2. Match the user's intent against `title`, `description`, and `category`.
3. If multiple entries match, present the top 3 candidates with their full
   `title` and `description` and ask the user to disambiguate.
4. If none match, surface the closest 3 by token overlap rather than
   inventing an id.

The JSON array does not carry `shortcut` / `command` / `requires_confirmation`
fields — those live only in the profile YAML. For confirmation behaviour,
inspect the action entry in `profile.base.yaml` / the consumer profile, or
just run with `--dry-run` first.

## Step 2 — Invoke

Once an `id` is chosen:

```sh
fastlane_cli run <action-id>                        # auto-resolve profile
fastlane_cli run <action-id> --profile <path>       # explicit profile
```

Useful flags for `run`:

- `--profile <path>` / `-p` — path to `profile.yaml` (a file or an app
  directory). Optional; omit to let walk-up discovery find it.
- `--option key=value` / `-o` — override a single command option. Repeatable.
  **The separator is `=`** (`--option flavor=staging`), not `:`. The CLI
  rewrites each pair into fastlane's `key:value` argument form internally.
  Only `fastlane`-type actions accept options; for other command types the
  flag is a no-op.
- `--dry-run` — print the resolved command (executable, args, env, cwd)
  without spawning fastlane. Use this to show the user what *would* happen
  before committing.

Note: `--lang tr|en` is a **top-level** flag, not a `run` flag — place it
before the subcommand (`fastlane_cli --lang en run <id>`). It is mainly a TUI
concern; `run` output is plain fastlane log text and `list` localizes from
the profile's `default_locale`.

Example with overrides:

```sh
fastlane_cli run internal_test --option bump=minor --option flavor=staging
fastlane_cli run ios_test_flight --dry-run --profile ./fastlane/profile.yaml
```

If the action is flagged `requires_confirmation: true` in the profile, warn
the user that the lane mutates remote state (version bump, store upload). If
`requires_overwrite_confirmation: true`, warn that local metadata/screenshots
under the app's `fastlane/` folder will be overwritten by a remote pull.
`fastlane_cli run` is headless — it does **not** prompt for confirmation, so
that warning is the assistant's responsibility.

## Step 3 — Watch the output

`fastlane_cli run` streams fastlane log lines straight to stdout/stderr (plain
text, no TUI) and propagates the lane's exit code. The final coloured
**summary box** at the bottom of the stream is the canonical "what happened"
report (see the `fastlane-summary-log` skill). When relaying results back to
the user, quote the summary box body rather than re-summarising the noisy
intermediate log.

The discovery line `discovered: <abs path>` is printed on stderr when the
profile was resolved by walk-up / directory form — that is informational, not
an error.

## Mapping intent to action — heuristics

(Apply *after* you have the JSON listing — these are search hints, not a
substitute for `fastlane_cli list --json`.)

| User says (in any language)                              | Search hint                              |
| -------------------------------------------------------- | ---------------------------------------- |
| "internal test build / both platforms"                   | `internal_test` (general)                |
| "ship to TestFlight / iOS internal"                      | `ios_*` ∩ TestFlight / internal          |
| "ship to Play internal / Android beta"                   | `android_*` ∩ internal                   |
| "production release / live"                              | `*_production` / `*_app_store`           |
| "what version are we on / version status"                | `*version*`                              |
| "pull store listing / download metadata"                 | `*download*`                             |
| "push store listing / upload metadata"                   | `*update_metadata*`                      |
| "App Privacy / nutrition label"                          | `ios_*_app_privacy*`                     |

## Do not

- Run `fastlane_cli run <id>` with an `id` you have not just observed in the
  JSON listing for *this* profile.
- Use `:` as the `--option` separator — the CLI flag is `--option key=value`.
  (`key:value` is fastlane's *internal* argument form, produced by the CLI.)
- Invoke `fastlane` (`bundle exec fastlane ...`) directly — bypassing the
  CLI loses environment wiring (`FASTLANE_ROOT`, `FASTLANE_APP_ROOT`) and the
  summary-box channel.
- Strip or rewrite the summary box when relaying results.
