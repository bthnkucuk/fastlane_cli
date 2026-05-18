# skills/

Bundled Claude Code / Cursor skills that ship with `fastlane_cli`. Each
subdirectory contains a single `SKILL.md` with frontmatter
(`name`, `description` including trigger keywords) and an instruction body
for the assistant.

A future `fastlane_cli skills install` subcommand (Track C3 of the roadmap)
will copy this tree into the consumer's local Claude config. Until then,
this directory is the canonical source.

## Index

| Skill                                                                  | One-liner                                                                                              |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| [`fastlane-cli-setup`](fastlane-cli-setup/SKILL.md)                    | Scaffold a fresh `cli_profile.yaml` and required credential env vars for a Flutter project.            |
| [`fastlane-cli-run`](fastlane-cli-run/SKILL.md)                        | Translate a natural-language intent into `fastlane_cli run <action-id>` via runtime action discovery.  |
| [`fastlane-version-bump`](fastlane-version-bump/SKILL.md)              | Inspect or bump pubspec `version: X.Y.Z+N` and reconcile it with the stores.                            |
| [`fastlane-cli-version-bump`](fastlane-cli-version-bump/SKILL.md)      | Bump fastlane_cli's *own* `pubspec.yaml` + formula version per conventional-commits rules when shipping a PR. |
| [`fastlane-metadata-sync`](fastlane-metadata-sync/SKILL.md)            | Pull / push App Store and Play store listing text + screenshots + App Privacy.                          |
| [`fastlane-testflight`](fastlane-testflight/SKILL.md)                  | iOS TestFlight release flow — credentials, version handling, canonical action ids.                      |
| [`fastlane-play-internal`](fastlane-play-internal/SKILL.md)            | Android Play Console internal-track release flow — service account, version handling, action ids.       |
| [`fastlane-doctor`](fastlane-doctor/SKILL.md)                          | Diagnose env / credential / toolchain issues before invoking a lane.                                    |
| [`fastlane-summary-log`](fastlane-summary-log/SKILL.md)                | Author the mandatory coloured summary box at the end of every user-facing lane / bridge command.        |

## Authoring rules

- The frontmatter `name` is kebab-case and matches the directory name.
- The `description` is a single sentence that ends with
  `Triggers on: <comma-separated keywords>`. Triggers should not ambiguously
  overlap across skills (e.g. "testflight" fires only `fastlane-testflight`).
- Body content references real action ids from
  [`fastlane/cli_profile.base.yaml`](../fastlane/cli_profile.base.yaml) and
  real lane names from
  [`fastlane/ios/Fastfile`](../fastlane/ios/Fastfile) /
  [`fastlane/android/Fastfile`](../fastlane/android/Fastfile) /
  [`fastlane/Fastfile`](../fastlane/Fastfile). No invented ids.
- Env vars are referenced exactly as documented in
  [`CLAUDE.md`](../CLAUDE.md) §5.3 and the Fastfile headers.
- No app-specific values (no real bundle ids, app names, or API keys).
