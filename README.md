# fastlane_cli

> **Note on `flutter clean` in lanes:** the shared `internal_test` lane (and any caller passing `run_clean: true`) used to invoke `flutter clean` directly, which takes **5+ minutes** in Firebase-via-SwiftPM Flutter apps because `xcodebuild clean` re-resolves the SwiftPM package graph per scheme. As of [Fastfile L228](fastlane/Fastfile#L228), that step is replaced with a targeted `rm -rf` of `build`, `.dart_tool`, and the iOS ephemeral/Flutter-framework artifacts — same end state, ~5 seconds instead of ~322 seconds. `Podfile.lock` is intentionally left intact. Tracking: [flutter#173940](https://github.com/flutter/flutter/issues/173940), [flutter#180758](https://github.com/flutter/flutter/issues/180758).

Terminal-first Fastlane assistant for Nocterm with:

- Fancy shell UI (sidebar + content + command bar)
- Category pages (`home`, `android`, `ios`, `general`, `guides`)
- Sidebar quick actions from profile shortcuts
- Slash palette (`/`) for page/action navigation
- Command execution with live logs
- Run progress section with active file indicator
- Metadata/screenshot path preflight validation
- Overwrite confirmation for risky download actions
- Guide pages for fixing folder structure issues

## Generic Fastlane templates

`packages/fastlane_cli/fastlane/` includes reusable Fastlane lane templates:

- `Fastfile` (shared lanes)
- `android/Fastfile`
- `ios/Fastfile`

App projects can keep metadata/screenshots/.env under their own `fastlane/`
directory and import the generic templates from their app `fastlane/Fastfile`.

## Run

```bash
fvm dart run fastlane_cli --profile /absolute/path/to/cli_profile.yaml
```

### Options

- `--profile <path>`: profile yaml path (required)
- `--lang tr|en`: override UI language
- `--dry-run`: print commands without executing

## Routing

Navigation is implemented with the [zenrouter_nocterm](https://github.com/definev/zenrouter/tree/feat/zenrouter_nocterm) Coordinator pattern (see `lib/src/routing/`). The coordinator owns four paths:

- `topTabsPath` — `IndexedStackPath` for the fixed top tabs (Home / Android / iOS / General / Guides).
- `runTabsPath` — custom `StackPath` (Chrome-style) for dynamic run tabs; opens or focuses by `actionId`.
- `palettePath` — custom `StackPath` modeled on `MiniPlayerPath`: an always-visible compact text field, expanded into a suggestion list when the user types or presses `/`.
- `overlayPath` — `NavigationPath` for modal overlays (currently the quick-actions menu pushed via `Ctrl+P`).

Routes are typed (`HomeRoute`, `AndroidCategoryRoute`, `RunRoute(actionId:)`, etc.) — navigate via `coordinator.navigate(...)` / `coordinator.openRun(...)` rather than string paths. URI-based deep links work through `parseRouteFromUri` (e.g. `/run/<id>`, `/guides/<topic>?action=<id>`).

Per-tab state lives on the route itself: each `RunRoute` owns a `RunSessionController` that streams logs/status from `CommandExecutionService`, and is disposed when the tab is closed.
