---
name: fastlane-cli-run
description: Translate a natural-language request ("ship to internal", "build a TestFlight", "what's the current version") into a concrete `fastlane_cli run <action-id>` invocation. Triggers on: run, ship, deploy, release, build and upload, fire the lane, trigger, kick off, dispatch, "I want to ...", what action.
---

# fastlane_cli — run an action

Use this skill when the user describes an outcome (in plain English/Turkish)
and you must pick the correct `fastlane_cli` action to invoke.

**Critical rule**: do NOT rely on a hardcoded list of action ids. Action ids
are profile-dependent — the user's `cli_profile.yaml` may add, replace, or
remove entries on top of fastlane_cli's bundled `cli_profile.base.yaml`.
Always discover the active set at runtime.

## Step 1 — Discover available actions

Call the JSON listing subcommand against the user's profile:

```sh
fastlane_cli list --json --profile <path-to-cli_profile.yaml>
```

Expected shape (one entry per resolved action, in profile order):

```json
{
  "default_locale": "tr",
  "supported_locales": ["tr", "en"],
  "shortcuts": ["internal_test", "ios_test_flight", "..."],
  "categories": [
    {
      "id": "ios",
      "title": {"tr": "iOS", "en": "iOS"},
      "actions": ["ios_test_flight", "ios_app_store", "..."]
    }
  ],
  "actions": [
    {
      "id": "ios_test_flight",
      "category": "ios",
      "title": {"tr": "iOS TestFlight", "en": "iOS TestFlight"},
      "description": {"tr": "...", "en": "..."},
      "shortcut": true,
      "requires_confirmation": false,
      "command": {
        "type": "fastlane",
        "platform": "ios",
        "lane": "test_flight",
        "options": {}
      }
    }
  ]
}
```

Parsing approach:

1. Build a flat `id → action` map from `actions[]`.
2. Match the user's intent against `title.en`, `title.tr`, `description.*`,
   and any tags in `shortcuts`. Prefer entries marked `shortcut: true` for
   ambiguous queries.
3. If multiple entries match, present the top 3 candidates with their full
   `title` and `description` and ask the user to disambiguate.
4. If none match, surface the closest 3 by token overlap rather than
   inventing an id.

## Step 2 — Invoke

Once an `id` is chosen:

```sh
fastlane_cli run <action-id> --profile <path-to-cli_profile.yaml>
```

Useful flags:

- `--lang tr|en` — UI / output language. Defaults to the profile's
  `default_locale`.
- `--dry-run` — print the materialized command (executable, args, env, cwd)
  without spawning fastlane. Use this when you want to show the user what
  *would* happen before committing.

If the action has `requires_confirmation: true`, warn the user that the lane
mutates remote state (version bump, store upload). If
`requires_overwrite_confirmation: true`, warn that local metadata/screenshots
under `fastlane/metadata/` will be overwritten by a remote pull.

## Step 3 — Watch the output

Lanes stream fastlane log lines into the TUI. The final coloured **summary
box** at the bottom of the stream is the canonical "what happened" report
(see the `fastlane-summary-log` skill). When relaying results back to the
user, quote the summary box body rather than re-summarising the noisy
intermediate log.

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
- Invoke `fastlane` (`bundle exec fastlane ...`) directly — bypassing the
  CLI loses environment wiring (`FASTLANE_ROOT`, `FASTLANE_APP_ROOT`,
  `BUNDLE_GEMFILE`) and the summary-box channel.
- Strip or rewrite the summary box when relaying results.
