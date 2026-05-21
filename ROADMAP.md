# Roadmap — from extracted package to brew-installable CLI + skills surface

Goal: any Flutter project can `brew install <owner>/fastlane_cli/fastlane_cli`,
drop a `cli_profile.yaml`, and get:

1. A TUI for interactive lane discovery (existing behavior).
2. Terminal subcommands for every lane (CI-friendly, scriptable, completion-aware).
3. Bundled Claude skills the developer can drop into their project's
   `.claude/skills/` (or `~/.claude/skills/`) for fast natural-language integration.

This file is structured for **parallel execution**. Each task block is a
self-contained brief a sub-agent can pick up; cross-track dependencies are
explicit. The supervisor (Claude main) dispatches tracks, verifies acceptance,
and promotes to the next wave.

---

## §0. Blockers — resolved

- [x] **LICENSE**: MIT (committed as `LICENSE` at repo root).
- [x] **GitHub owner / repo**: `bthnkucuk/fastlane_cli`. The future Homebrew
      tap lives at `bthnkucuk/homebrew-fastlane_cli`.
- [x] **Brew dep policy**: `depends_on "fastlane"` confirmed in the formula
      (see [dist/homebrew/Formula/fastlane_cli.rb](dist/homebrew/Formula/fastlane_cli.rb)).

---

## Track A — Dart core (runner resolution + subcommand layer)

Owner: one agent end-to-end; A1 → A2 sequential.

### A1. Runner asset auto-resolve
**Depends on**: nothing.

Replace the mandatory `fastlane_runner_path:` field in `cli_profile.yaml`
with an auto-resolver. Resolution order:

1. Profile override (`fastlane_runner_path`) if set.
2. `Platform.resolvedExecutable` → walk up to find `share/fastlane_cli/fastlane/`
   (brew layout) or `<repo>/fastlane/` (source layout).
3. `Isolate.resolvePackageUri('package:fastlane_cli/_dummy.dart')` for
   `dart pub global activate` users.
4. Throw a clear "fastlane runner not found" error listing paths tried.

**Files**: new `lib/src/services/runner_resolver.dart`; update
`lib/src/services/profile_loader.dart` to make `fastlane_runner_path` optional.

**Acceptance**:
- `dart run bin/fastlane_cli.dart --profile <p>` works in repo-local source mode,
  AOT-compiled binary mode, and simulated brew layout — without
  `fastlane_runner_path` set in profile.
- Tests cover all 4 resolution branches (temp dir + fake brew layout fixture).

### A2. Subcommand layer (CommandRunner)
**Depends on**: A1.

Refactor `bin/fastlane_cli.dart` from a single TUI entry into a `CommandRunner`.
Subcommands:

- *(no command)* → existing TUI (backwards compatible).
- `run <action-id> [--option key=value ...]` → headless lane execution.
- `list [--category <id>] [--json]` → enumerate actions from profile.
- `doctor` → environment check (Ruby/fastlane/bundle/env). **Implementation
  in Track B**; A2 just wires the shell.
- `init [--app-name <n>] [--platform ios|android|both]` → scaffold
  `cli_profile.yaml` in cwd.
- `skills install [--global|--project] [--force] [--dry-run]` →
  **implementation in Track C**; A2 wires the shell.
- `completion <bash|zsh|fish>` → emit shell completion using profile actions.

Profile resolution: `--profile` → `./cli_profile.yaml` → `$FASTLANE_CLI_PROFILE`
→ error with remediation message.

**Files**: `bin/fastlane_cli.dart`, new `lib/src/cli/` dir for command classes,
update `FastlaneCliLauncher` so TUI path is one of many.

**Acceptance**:
- `fastlane_cli list --json` outputs valid JSON of action IDs/titles.
- `fastlane_cli run <action-id>` runs a lane non-interactively, propagates the
  lane's exit code.
- `fastlane_cli` (no args) still opens TUI when profile is discoverable.
- All existing tests pass; new tests per subcommand.

---

## Track B — Setup / doctor / bundle cache

Owner: one agent. B1 logic can develop in parallel with A1/A2; B2 needs A2.

### B1. Vendor bundle → user cache
**Depends on**: nothing for logic; A2 for CLI integration.

Move `bundle install --path vendor/bundle` from repo-local to user cache:
- macOS: `~/Library/Caches/fastlane_cli/bundle/<ruby-abi>`
- Linux: `~/.cache/fastlane_cli/bundle/<ruby-abi>`

Slim `fastlane/Gemfile` to the minimum needed by `storepilot_bridge.rb`
(`googleauth` + `google-apis-androidpublisher_v3`). Lanes themselves use the
system/brew `fastlane` gem.

At lane-run time set `BUNDLE_PATH=<user-cache>` and
`BUNDLE_GEMFILE=<runner>/Gemfile` in `CommandBuilder._buildFastlane`.

**Files**: `fastlane/Gemfile`, `lib/src/services/command_builder.dart`,
new `lib/src/services/bundle_cache.dart`.

**Acceptance**: lane runs after a single first-time bundle install with no
manual steps; bundle cache reused across runs.

### B2. `doctor` subcommand body
**Depends on**: A2 shell + B1 cache logic.

Implement `fastlane_cli doctor`:
- `fastlane --version` ≥ supported.
- `ruby --version` ≥ 3.2.
- Bundle cache exists; if missing, run `bundle install --path <cache>`.
- Credentials env vars present for declared platforms (warn-only).

First-run hook: if bundle cache empty when a lane fires, auto-invoke doctor
with a one-line "first-run setup" notice.

**Files**: `lib/src/cli/doctor_command.dart`, extend
`lib/src/services/preflight_validator.dart`.

**Acceptance**: `fastlane_cli doctor` on a fresh machine exits 0 after one-time
bundle install; reruns are <1s.

---

## Track C — Skills bundle

Owner: one agent for C1+C2 authoring; C3 needs A2 shell.

### C1. Skills directory + index
**Depends on**: nothing.

Create `skills/` at repo root with one SKILL.md per feature. `.claude/skills`
is a symlink to this tree so the same skills auto-load when Claude Code runs
inside the fastlane_cli repo itself.

Initial skill set:
- `fastlane-cli-setup` — scaffold `cli_profile.yaml` + env from a Flutter project.
- `fastlane-cli-run` — natural language ↔ `fastlane_cli run …`. **MUST** call
  `fastlane_cli list --json` at runtime, not hardcode action IDs.
- `fastlane-version-bump` — version status + bump flows.
- `fastlane-metadata-sync` — store metadata pull/push.
- `fastlane-testflight` — iOS TestFlight release flow.
- `fastlane-play-internal` — Android Play internal track flow.
- `fastlane-doctor` — diagnose env/credential issues.
- `fastlane-summary-log` — (migrated) for lane authors.

Each SKILL.md frontmatter: `name`, `description`, trigger keywords (terms the
user might say).

**Files**: `skills/<skill-name>/SKILL.md` per skill; `skills/README.md` index.

**Acceptance**: every SKILL.md parses; trigger keywords don't ambiguously
overlap.

### C2. Skill content review
**Depends on**: C1.

Cross-check each skill against actual lanes in `fastlane/ios/Fastfile` +
`fastlane/android/Fastfile`. Ensure skills:
- Quote only lane names / action IDs that actually exist.
- Reference `cli_profile.base.yaml` action IDs verbatim.
- Discover available actions via `fastlane_cli list --json` at runtime
  rather than hardcoding them.

**Acceptance**: smoke-run each skill against a sample profile; no
hallucinated action IDs in any skill body.

### C3. `skills install` subcommand
**Depends on**: A2 shell + C1 content.

Implement `fastlane_cli skills install`:
- `--global` → copy bundled `skills/*` to `~/.claude/skills/`.
- `--project` (default) → copy to `<cwd>/.claude/skills/`.
- `--dry-run` → list what would be copied.
- Refuse to overwrite existing skill dirs unless `--force`.

Source path: brew install → `<prefix>/share/fastlane_cli/skills/`; dev mode →
`<repo>/skills/`. Use runner-resolver (A1) to locate.

**Files**: `lib/src/cli/skills_install_command.dart`.

**Acceptance**: from any directory with no `.claude/skills/` present,
`fastlane_cli skills install --project` populates it with the bundled skills;
re-running without `--force` is a no-op with a clear message.

---

## Track D — Release pipeline (GH Actions)

Owner: one agent. Skeleton can land Wave 1; final wiring needs A2 + B1 + C1.

### D1. `.github/workflows/release.yml`
**Depends on**: A2 + B1 + C1 for the final tarball shape.

Build + tarball matrix:
- `macos-14` (arm64), `macos-13` (x86_64), `ubuntu-latest` (x86_64).
- Per leg: setup-dart 3.6.x → `dart pub get` → `dart test` (fail-fast) →
  `dart compile exe bin/fastlane_cli.dart -o build/fastlane_cli` →
  `tar -czvf fastlane_cli-<os>-<arch>.tar.gz build/fastlane_cli fastlane/ skills/ README.md LICENSE`.
- Compute sha256 per tarball; embed into release body.
- Trigger: tag push `v*.*.*`.

**Acceptance**: pushing `v0.1.0` produces 3 tarballs with matching `.sha256`
lines in the release body.

### D2. Tap auto-update
**Depends on**: D1 + E1.

On successful release, `repository_dispatch` to the tap repo with new version +
urls + shasums; tap repo CI opens a PR updating `Formula/fastlane_cli.rb`.

**Acceptance**: tag push → tap PR opens within 5 min.

---

## Track E — Homebrew tap

Owner: one agent. Skeleton parallel-safe; final URLs/SHAs need D1.

### E1. Tap skeleton + formula
**Depends on**: A2 + C3 for final install layout; D1 for real URLs/SHAs.

Create `homebrew-fastlane_cli` repo (separate from this one) with
`Formula/fastlane_cli.rb`:

```ruby
class FastlaneCli < Formula
  desc "Terminal-first Fastlane assistant for Flutter projects"
  homepage "https://github.com/<owner>/fastlane_cli"
  version "0.1.0"

  on_macos do
    on_arm do
      url "https://github.com/.../fastlane_cli-macos-arm64.tar.gz"
      sha256 "..."
    end
    on_intel do
      url "https://github.com/.../fastlane_cli-macos-x86_64.tar.gz"
      sha256 "..."
    end
  end
  on_linux do
    url "https://github.com/.../fastlane_cli-linux-x86_64.tar.gz"
    sha256 "..."
  end

  depends_on "fastlane"

  def install
    bin.install "build/fastlane_cli"
    (share/"fastlane_cli").install "fastlane"
    (share/"fastlane_cli").install "skills"
  end

  def caveats
    <<~EOS
      To drop the bundled Claude skills into your project, run:
        fastlane_cli skills install --project
      Or globally for all projects:
        fastlane_cli skills install --global
    EOS
  end

  test do
    assert_match "fastlane_cli", shell_output("#{bin}/fastlane_cli --help")
  end
end
```

**Acceptance**: a fresh user runs `brew install <tap>/fastlane_cli &&
fastlane_cli --help` with no prior Dart/Flutter setup, sees help text.

---

## Track F — Docs

Owner: one agent. Quickstart/install draft can land Wave 1 with placeholders;
subcommand + skills sections need A2 + C1 final.

### F1. README
- 30-second pitch + animated screencast (asciinema).
- Install (brew + dev-from-source).
- Quickstart: minimal `cli_profile.yaml` for a fresh Flutter app.
- Subcommand reference (Track A2 outputs).
- Skills reference (Track C outputs).
- Schema reference for `cli_profile.yaml` (merge rules from
  `cli_profile.base.yaml`).
- Credentials matrix (env vars per lane).
- Troubleshooting.

### F2. CONTRIBUTING + lane-author guide
- Summary-box mandate ([`fastlane-summary-log`](skills/fastlane-summary-log/SKILL.md)).
- How to add a new action to base/profile.

---

## Track G — Opportunistic cleanups *(parallel-safe anytime)*

- [ ] `TEST_QUALITY_REPORT.md` — historical, mentions monorepo context. Strip
      preamble or delete.
- [ ] `fastlane/README.md`, `fastlane/Preview.html` — leftover fastlane init
      files; trim or remove.
- [ ] Cull `dependency_overrides:` in `pubspec.yaml` — `meta: 1.18.0` was a
      monorepo workaround; verify still needed.
- [ ] Tighten `analysis_options.yaml` (no `print`, no `.hardcoded`).

---

## Execution waves *(for supervisor)*

| Wave | Track / task | Agent role | Blocks on |
|---|---|---|---|
| 0 | §0 decisions | user | — |
| **1** *(parallel)* | A1 runner resolve | Dart agent | wave 0 |
| | B1 bundle cache logic | Ruby+Dart agent | wave 0 |
| | C1 skills authoring | Skills agent | wave 0 |
| | C2 skill content review | Skills agent | C1 |
| | D1 release.yml skeleton | CI agent | wave 0 (placeholder paths) |
| | E1 formula skeleton | Brew agent | wave 0 (template) |
| | F1 README draft (install + quickstart) | Docs agent | wave 0 |
| | G cleanups | any free agent | — |
| **2** *(parallel after A1)* | A2 subcommand layer | Dart agent | A1 |
| **3** *(parallel after A2)* | B2 doctor body | Setup agent | A2 + B1 |
| | C3 `skills install` cmd | Skills agent | A2 + C1 |
| | D1 finalize tarball shape | CI agent | A2 + B1 + C1 |
| | F1 finalize (subcommand + skills sections) | Docs agent | A2 + C1 |
| | E1 finalize install block | Brew agent | A2 + C3 |
| **4** *(sequential)* | D2 tap auto-update | CI agent | D1 + E1 |
| | E1 publish formula with real URLs/SHAs | Brew agent | D1 release |
| | release v0.1.0 | supervisor | all above |

**Supervisor responsibilities** (Claude main):
- Dispatch each wave's tracks in parallel via sub-agents.
- Verify acceptance criteria per task before promoting to next wave.
- Resolve cross-track conflicts (e.g. profile schema changes touching A2 + C2).
- Keep this file in sync with task statuses.

---

## §7. Post-1.0 nice-to-haves

- [ ] JSON output mode for `storepilot_bridge` queries (machine-readable status).
- [ ] Notarize macOS binaries (`xcrun notarytool`).
- [ ] Cross-platform tests on GH Actions matrix (today: only macOS local).
- [ ] Submit to `homebrew-core` once 75+ stars + 30 days.
