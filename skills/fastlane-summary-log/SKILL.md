---
name: fastlane-summary-log
description: Add a coloured, box-bordered "human summary" log block to fastlane lanes and storepilot_bridge commands. Use whenever you author or edit a lane that mutates pubspec/build artifacts/store metadata, or when adding a new bridge command — the summary lets the user see at a glance what happened, with which inputs, and from which sources, without scanning the noisy fastlane log.
---

# Fastlane summary log

Every user-facing fastlane lane and every storepilot bridge command MUST end
with a structured, coloured summary box rendered via
`FastlaneCliConfig.summary_box` / `FastlaneCliConfig.print_summary_box`.

The summary box is **not** a replacement for fastlane's own log lines — it is a
final "human report" rendered after the lane's real work, so the user can see
the meaningful facts at a glance inside the noisy fastlane stream.

## When to add a summary box

Add one whenever the lane / command:
- mutates state (pubspec, build artifact, store listing, metadata download)
- reads non-trivial state from a remote (Play Store, App Store Connect)
- would otherwise leave the user scanning hundreds of log lines for the answer

Do **not** add one for:
- private helper lanes that only return values to a parent lane
- pure path-resolution helpers
- lanes whose only purpose is to alias another lane (`deploy_testflight`)

## Required fields per box

The box title is short ("App · Action") in this style:
- `Version data`
- `Pubspec versiyon güncellendi`
- `Android · Internal Testing yüklendi`
- `iOS · TestFlight yüklendi`

The body MUST include — when applicable to the lane — one labelled line per item:
1. **App / package / bundle identifier** — what was acted on.
2. **Flavor** — `(none)` if absent.
3. **Path or artifact** — absolute path to the file/AAB/IPA/metadata folder.
4. **Source** — *where* a fetched value came from
   (e.g. `google_play_track_releases`, `Spaceship app_store_build_number(live: false)`, `pubspec.yaml`).
5. **Rule** — when a value is *computed* (max semver, build_number+1, max(android, ios, pubspec)),
   spell out the computation so the user does not have to reverse-engineer it.
6. **Strategy** — when a value is *written* (regex replacement on pubspec, force-deliver), spell that out.
7. **Outcome / next** — track, release_status, "tetiklendi/atlandı", etc.

Use `:sep` as a list element to insert a horizontal divider inside the box.

## How to call it

```ruby
FastlaneCliConfig.print_summary_box(
  "Android · Production yüklendi",
  [
    "Package        : #{package_name}",
    "Flavor         : #{flavor || '(none)'}",
    "Track          : #{track}",
    "Release status : #{release_status}",
    "Auto version   : #{auto_version}",
    "AAB            : #{aab_path}"
  ]
)
```

For end-of-lane summaries inside `lane :foo do |options|` blocks, prefer
`print_summary_box` — it routes through `FastlaneCore::UI.message` so the lines
appear in the fastlane log stream and are captured by Dart's
[command_execution_service.dart](../../lib/src/services/command_execution_service.dart)
listener.

For the storepilot bridge (which writes JSON to STDOUT and must keep that
stream clean), use `FastlaneCliConfig.summary_box(...)` to *build* the lines
into the JSON's `summary` field, and additionally `warn(summary)` to emit them
on STDERR for live visibility.

## Style invariants

- Border colour: bright cyan (`\e[96m`)  — set by `SUMMARY_BOX_BORDER_COLOR`.
- Title colour: bold bright magenta (`\e[1;95m`) — set by `SUMMARY_BOX_TITLE_COLOR`.
- Width: 78 columns (`SUMMARY_BOX_WIDTH`).
- Box characters: `┌ ─ ┐ │ ├ ┤ └ ┘`.
- Lines longer than the inner width wrap on whitespace.
- Honours `NO_COLOR=1` — colours stripped automatically.

Do NOT:
- Use a different border / colour / width.
- Hand-roll your own ASCII box ("====", "----").
- Mix `puts` and `print_summary_box` for the same summary — pick one channel.
- Print the box BEFORE the lane's real work — it must be the closing log.

## Adding a new bridge command

1. In [storepilot_bridge.rb](../../fastlane/storepilot_bridge.rb),
   build a structured report hash exactly like `collect_version_report`.
2. Render `summary_box(title, lines)` and stash the joined string into the
   response hash under `"summary"`.
3. Mirror it to STDERR via `warn(report["summary"])` so it shows up live.
4. Keep the JSON contract on STDOUT clean — never `puts` the box to STDOUT.

## Reference implementation

- Helper: [common_helpers.rb](../../fastlane/common_helpers.rb) `summary_box`, `print_summary_box`.
- Lane example: [Fastfile](../../fastlane/Fastfile) `get_version_data`.
- Bridge example: [storepilot_bridge.rb](../../fastlane/storepilot_bridge.rb) `update_development_pubspec_version` + `format_update_summary`.
