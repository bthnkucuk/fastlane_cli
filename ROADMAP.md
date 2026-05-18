# Roadmap — from extracted package to brew-installable CLI

Goal: `brew install <owner>/fastlane_cli/fastlane_cli` → any Flutter project
can drop a `cli_profile.yaml` next to its own `fastlane/` folder and run lanes
without bundling the Ruby/Fastlane runner.

This is the punch list. Each section is a discrete, mergeable chunk.

---

## 0. Pending decisions (block work)

- [ ] **LICENSE choice** — Apache-2.0 or MIT. Add as `LICENSE` at repo root.
- [ ] **GitHub owner / repo name** — pick the org/user that will host the repo (e.g. `<owner>/fastlane_cli`).
- [ ] **Brew dep policy** — confirm `depends_on "fastlane"` in the formula
      (recommended over "user brings their own Ruby"). See discussion in
      [CLAUDE.md §6](CLAUDE.md).

Until 0.1 and 0.2 are answered, the formula and the README header lines
remain templated.

---

## 1. Runner asset auto-resolve  *(small, mostly mechanical)*

The CLI must locate its bundled `fastlane/` runner without depending on a
`fastlane_runner_path:` line in the consumer's `cli_profile.yaml`.

- [ ] Add `runner_resolver.dart` (or extend `profile_loader.dart`) with:
      1. If profile sets `fastlane_runner_path` → use it (override).
      2. Else: resolve via `Platform.resolvedExecutable`, walk up to find
         `share/fastlane_cli/fastlane/` (brew layout) or `<repo>/fastlane/`
         (dev/source layout).
      3. Else: try `Isolate.resolvePackageUri('package:fastlane_cli/_dummy.dart')`
         then `..resolve('../fastlane/')` (for `dart pub global activate` users).
      4. Throw a clear "fastlane runner not found" error listing the paths
         that were tried.
- [ ] Make `fastlane_runner_path` in `cli_profile.yaml` optional in the
      profile schema; update `profile_loader.dart` validation.
- [ ] Tests: add cases for each resolution branch (use a temp dir + fake
      `share/fastlane_cli/` layout to simulate brew install).

### Acceptance
Running `dart run bin/fastlane_cli.dart --profile <path>` against a profile
that does NOT declare `fastlane_runner_path` works in:
- repo-local source mode (`dart run`)
- AOT-compiled binary mode (`dart compile exe` next to `fastlane/`)
- simulated brew layout (binary at `bin/`, fastlane at `share/fastlane_cli/fastlane/`)

---

## 2. Vendor bundle → user cache  *(medium, UX-shaping)*

`fastlane/vendor/` is git-ignored already, but local dev still expects
`bundle install --path vendor/bundle`. For brew distribution that approach
fails (read-only Cellar, platform-specific binaries).

- [ ] Slim `fastlane/Gemfile` to the strict minimum needed by
      `storepilot_bridge.rb` (the lanes themselves rely on the system
      `fastlane` gem; bridge needs `googleauth` + `google-apis-androidpublisher_v3`).
- [ ] Decide bundle install location:
      - macOS: `~/Library/Caches/fastlane_cli/bundle/<ruby-abi>`
      - Linux: `~/.cache/fastlane_cli/bundle/<ruby-abi>`
- [ ] Add `fastlane_cli doctor` (or `setup`) subcommand:
      - Check `fastlane --version` (system / brew dep).
      - Check Ruby ≥ 3.2.
      - Run `bundle install --path <user-cache>` against the bundled Gemfile.
      - On lane run, set `BUNDLE_PATH=<user-cache>` and `BUNDLE_GEMFILE=<runner>/Gemfile`.
- [ ] First-run hook: if `BUNDLE_PATH` is empty when a lane fires, invoke
      `doctor` automatically with a one-line "first-run setup" notice.
- [ ] Documentation: README "first run" section + troubleshooting.

### Acceptance
Fresh user runs `brew install fastlane_cli && fastlane_cli --profile <profile>`
and either (a) lane runs after a single first-time bundle install with no manual
steps, or (b) the CLI fails with a clear remediation message naming the exact
`fastlane_cli doctor` command.

---

## 3. Release build pipeline  *(medium, infra)*

Produce signed binaries for every supported platform on tag push.

- [ ] `.github/workflows/release.yml`:
      - matrix: `[macos-14 (arm64), macos-13 (x86_64), ubuntu-latest (x86_64)]`
      - steps per leg:
        1. setup dart 3.x
        2. `dart pub get`
        3. `dart test`  *(fail-fast)*
        4. `dart compile exe bin/fastlane_cli.dart -o build/fastlane_cli`
        5. `tar -czvf fastlane_cli-<os>-<arch>.tar.gz build/fastlane_cli fastlane/ README.md LICENSE`
        6. upload tarball as release asset
      - on success: bump the homebrew tap formula (see §4) via a single
        `gh release` + `repository_dispatch` to the tap repo.
- [ ] Code-signing for macOS? Probably skip the first release (`spctl` will
      warn but `brew install` works). Add notarization later.
- [ ] Reproducibility: lock Dart version in workflow (`dart-version: 3.6.x`),
      checksum tarballs into release body.

### Acceptance
Pushing `v0.1.0` tag produces three tarballs on the GitHub Release page, each
with a matching `.sha256` line in the release body.

---

## 4. Homebrew tap  *(small, mechanical after §3)*

- [ ] Create `homebrew-fastlane_cli` repo (separate from this one).
      Path: `Formula/fastlane_cli.rb`.
- [ ] Formula skeleton:
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
        end

        test do
          assert_match "fastlane_cli", shell_output("#{bin}/fastlane_cli --help")
        end
      end
      ```
- [ ] Wire the tap repo to auto-update formula on this repo's release
      (GitHub Action: `repository_dispatch` → checkout tap → sed urls+shasums → PR).
- [ ] Manual smoke test on a fresh user: `brew tap`, `brew install`, run.

### Acceptance
A bystander with no prior Dart/Flutter setup can run
`brew install <owner>/fastlane_cli/fastlane_cli && fastlane_cli --help` and
see the help text.

---

## 5. README + public docs

- [ ] Top-of-readme: 30-second pitch + animated screencast (asciinema).
- [ ] Install section (brew + dev-from-source).
- [ ] Quickstart: minimal `cli_profile.yaml` for a fresh Flutter app.
- [ ] Schema reference for `cli_profile.yaml` (and how it merges with the
      bundled `cli_profile.base.yaml`).
- [ ] "Writing a new lane" guide (with summary-box mandate).
- [ ] Credentials matrix (env vars and what each lane consumes).
- [ ] Troubleshooting (Ruby version, fastlane plugin install, etc.).

---

## 6. Cleanups deferred from the extraction

These were left as-is during the move; address opportunistically:

- [ ] `TEST_QUALITY_REPORT.md` — historical, mentions monorepo context. Either
      strip the historical preamble or delete.
- [ ] `fastlane/README.md`, `fastlane/Preview.html` — leftover fastlane init
      files; trim or remove.
- [ ] Cull `dependency_overrides:` in `pubspec.yaml` — `meta: 1.18.0` was a
      monorepo-driven workaround; verify it's still needed standalone.
- [ ] `analysis_options.yaml` — currently inherits `lints: ^6.1.0`. Tighten
      project-specific rules (no `print`, no `.hardcoded`).

---

## 7. Nice-to-haves (post-1.0)

- [ ] `--action <id>` flag to skip the TUI and fire one lane directly (useful
      for CI).
- [ ] JSON output mode for `storepilot_bridge` queries (machine-readable status).
- [ ] `fastlane_cli init` — scaffold a `cli_profile.yaml` in the current
      Flutter project.
- [ ] Cross-platform tests on the GH Actions matrix (today: only macOS local).
- [ ] Notarize macOS binaries (`xcrun notarytool`).
- [ ] Submit to `homebrew-core` once 75+ stars + 30 days.

---

## Execution order

1. §0 — answer pending decisions (10 min).
2. §1 — runner auto-resolve (1-2 h).
3. §2 — vendor → user cache (2-3 h, includes README touchups).
4. §3 — release pipeline (2-3 h).
5. §4 — homebrew tap + smoke test (1 h).
6. §5 — README polish (1-2 h).
7. §6 — opportunistic cleanups.
