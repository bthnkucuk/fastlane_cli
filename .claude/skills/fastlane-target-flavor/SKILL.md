---
name: fastlane-target-flavor
description: Resolve the Flutter entry-point file (`--target lib/main_*.dart`) and `--flavor` for a fastlane lane invocation in this CLI. Use whenever a user hits `Target file "lib/main.dart" not found`, asks how to point a lane at `main_<flavor>.dart`, configures a multi-flavor app, or wires a new lane that calls `flutter build apk|appbundle|ipa`.
---

# Fastlane target & flavor resolution

Flutter apps consumed by this CLI often have multiple entry points
(`lib/main_narravo.dart`, `lib/main_tuspeech.dart`, …) and multiple flavors.
The fastlane lanes here resolve both via a single helper —
`FastlaneCliConfig.flutter_target` in
[fastlane/common_helpers.rb](fastlane/common_helpers.rb) — and an accompanying
`FastlaneCliConfig.resolve_flavor`. Anything that builds the app
(`flutter build apk|appbundle|ipa`) MUST go through these helpers so the user
has consistent overrides across every lane.

## Resolution order (target)

`flutter_target(options)` returns the first non-blank match, in this order:

1. **Per-invocation option** — `target:` or `flutter_target:` on the fastlane
   command line. Highest precedence; for one-off runs.
   ```sh
   fastlane internal_test platform:ios target:lib/main_narravo.dart
   ```
2. **Env var** — `FASTLANE_FLUTTER_TARGET` or `FLUTTER_TARGET`. Survives the
   shell session; can live in the app's `.env`.
   ```sh
   export FASTLANE_FLUTTER_TARGET=lib/main_narravo.dart
   ```
3. **Flavor convention** — if a flavor is resolved AND
   `lib/main_<flavor>.dart` exists under the app root, that file is used.
   ```sh
   fastlane internal_test platform:ios flavor:narravo
   # → adds both --flavor narravo and --target lib/main_narravo.dart
   ```
4. **`nil`** — the helper returns nil; the lane omits `--target` and Flutter
   falls back to `lib/main.dart`. This is the source of
   `Target file "lib/main.dart" not found` when the consumer app does not
   have a `main.dart`.

## Resolution order (flavor)

`resolve_flavor(options)` mirrors the same shape:

1. `flavor:` option on the command line.
2. Env vars, first match wins: `FASTLANE_FLAVOR`, `APP_FLAVOR`, `FLAVOR`.
3. `nil` — flavor omitted from the build.

The flavor result also feeds the target convention in step 3 above, so for an
app whose entry point matches `lib/main_<flavor>.dart`, **setting flavor alone
is enough** — target is implied.

## When the user asks "how do I point this lane at `main_X.dart`?"

Recommend in this order, falling back if a prerequisite is missing:

1. **Flavor convention** (preferred) — only if the app actually uses a
   `--flavor` *and* its entry file matches the `lib/main_<flavor>.dart`
   convention. One knob, two effects.
2. **Profile-level option** in the consumer's `cli_profile.yaml` — when the
   entry should always be the same for that app:
   ```yaml
   actions:
     - id: internal_test
       options:
         target: lib/main_narravo.dart
         flavor: narravo
   ```
3. **Env var** — for shell/CI scoping without editing the profile.
4. **Per-invocation option** — one-off override.

Reach for `dependency_overrides`-style hacks (hardcoding into the Fastfile)
NEVER — see §"No app-specific values" in [CLAUDE.md](CLAUDE.md).

## Writing a new lane that builds the app

Every lane that shells out to `flutter build …` MUST go through both helpers
and only append the flags when non-blank. Reference pattern in
[fastlane/Fastfile](fastlane/Fastfile):

```ruby
target = FastlaneCliConfig.flutter_target(options)
flavor = FastlaneCliConfig.resolve_flavor(options)

build_parts = ["#{flutter_cmd} build ipa --release"]
build_parts << "--flavor #{Shellwords.escape(flavor)}" unless FastlaneCliConfig.blank?(flavor)
build_parts << "--target #{Shellwords.escape(target)}" unless FastlaneCliConfig.blank?(target)
sh(FastlaneCliConfig.in_app_root(build_parts.join(" "), options))
```

Do NOT:
- Hardcode `lib/main.dart` (or any other path) in the lane.
- Read `ENV["FLUTTER_TARGET"]` directly — go through `flutter_target`, which
  honours the full precedence chain.
- Pass `--target` / `--flavor` unconditionally — Flutter errors out when given
  a blank value. Always guard with `unless FastlaneCliConfig.blank?(…)`.
- Re-implement the `lib/main_<flavor>.dart` convention in a new place — extend
  the helper instead so every lane benefits.

## Surfacing the resolved values

If a lane prints a summary box (see [[fastlane-summary-log]]), include the
resolved values so the user can see *what was built*:

```ruby
"Flavor         : #{flavor || '(none)'}",
"Entry point    : #{target || 'lib/main.dart (default)'}",
```

This makes the `Target file "lib/main.dart" not found` class of error
self-diagnosing — the summary shows immediately whether the lane fell through
to the default.

## Reference

- Helper: [common_helpers.rb:191-204](fastlane/common_helpers.rb#L191-L204) (`flutter_target`),
  [common_helpers.rb:110-118](fastlane/common_helpers.rb#L110-L118) (`resolve_flavor`).
- Lane example (iOS build via `--target`): [fastlane/Fastfile:217-227](fastlane/Fastfile#L217-L227).
- Lane example (Android appbundle): [fastlane/android/Fastfile:150-154](fastlane/android/Fastfile#L150-L154).
- Related skill: [[fastlane-summary-log]] — exposes resolved values to the user.
- Repo rules: [CLAUDE.md](CLAUDE.md) §5.2 (no app-specific values), §5.3 (env-driven config).
