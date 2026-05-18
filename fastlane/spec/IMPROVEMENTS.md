# Ruby/Fastlane code audit — fastlane_cli

Scope: every Ruby file under `fastlane/` and `bin/` (six files, ~2,500 LOC).
Audit conducted alongside introduction of the RSpec suite under `fastlane/spec/`.

## Audit summary

| File | LOC | Tests added | Notable risk |
|---|---|---|---|
| `fastlane/common_helpers.rb` | 762 | 47 examples in `common_helpers_spec.rb` | env-fallback drift, summary-box rendering invariants |
| `fastlane/storepilot_bridge.rb` | 1,406 | 89 examples in `storepilot_bridge_spec.rb` | pubspec mutation correctness, OAuth payload shape, network shape stability |
| `fastlane/actions/google_play_track_releases.rb` | 68 | (covered by integration; thin pass-through) | none — straight delegation to `Supply::Client` |
| `fastlane/Fastfile` (top) | 316 | (covered transitively via common_helpers + bridge) | regex-only version parsing |
| `fastlane/ios/Fastfile` | 712 | (lanes integration only) | three lanes lack summary boxes (see below) |
| `fastlane/android/Fastfile` | 457 | (lanes integration only) | two lanes lack summary boxes (see below) |
| `bin/sync_metadata_fallbacks.rb` | 81 | (manual; pure file I/O over `materialize_localised_fallbacks`, which is covered) | none |

RSpec total: **136 examples, 0 failures**.

Categorisation: 🔴 = real bug; 🟡 = risk / fragile; 🟢 = style / clarity.

---

## 🔴 Bugs (fix candidates)

No 🔴 issues were both (a) reproducible under a unit test and (b) safe to
patch in this audit. Two near-misses are noted as 🟡 because they require a
behavioural decision (the inline-comment regex limitation and the
documentation-drift around secret redaction) before being safe to land.

---

## 🟡 Risks (tests cover the current behaviour; refactor later)

### CLAUDE.md claims summary boxes "auto-redact known sensitive keys" but the helper does not
**File**: `fastlane/common_helpers.rb:691` (`summary_box`); CLAUDE.md §5.3.
**Finding**: `print_summary_box` / `summary_box` echo every line into the
fastlane log verbatim. No filter strips `password`, `api_key`, `token`,
`json_key_data`, etc. CLAUDE.md §5.3 reads "Never log secrets. The summary
box helper auto-redacts known sensitive keys." — that's currently false.
**Risk**: if a lane author drops a secret value into a summary line
(e.g. `"API key: #{ENV['APP_STORE_CONNECT_API_KEY_FILEPATH']}"`), it leaks
to logs. Existing lanes do not appear to do this, but the doc is misleading
to anyone adding a new lane.
**Recommended fix**: add a `redact_value(line)` helper that scans for
`(password|api[_-]?key|secret|token|private[_-]?key|json[_-]?key[_-]?data)\s*[:=]`
and replaces the trailing value with `***`. Apply inside `summary_box`
before the wrap step. Wire a test in `common_helpers_spec.rb`. Until then,
the doc claim should be softened to "Never log secrets — the helper does
NOT auto-redact."

### Pubspec version line ignores inline `# comments`
**File**: `fastlane/storepilot_bridge.rb:875` (`read_flutter_pubspec_version`),
also `fastlane/Fastfile:21` (`update_pubspec_version`).
**Finding**: regex `^\s*version:\s*([^\s#]+)\s*$` requires the line to end
with the version value (only optional trailing whitespace). A pubspec
written as `version: 1.0.0+7 # bump for review` fails to match, and the
bump silently writes a fresh version line at the top of the file (in
`Fastfile`'s `update_pubspec_version`) or returns "no version line found"
(in `bridge.bump_flutter_pubspec_build_number`).
**Recommended fix**: change to `^\s*version:\s*([^\s#]+)(?:\s+#.*)?\s*$`.
A spec for the post-fix behaviour is checklist-noted in
`storepilot_bridge_spec.rb` line ~228.

### `read_plist_value` references `stderr` from a stale binding inside its rescue
**File**: `fastlane/storepilot_bridge.rb:991-996`.
**Finding**:
```ruby
def read_plist_value(plist_path, key)
  _stdout, stderr, status = Open3.capture3(...)
  ...
rescue StandardError
  error_message = stderr.to_s.strip   # NameError when Open3 itself raises
  raise BridgeError, "Info.plist okunamadi (#{key}): #{error_message}" unless error_message.empty?
  nil
end
```
If `Open3.capture3` raises before the multiple-assignment completes, the
rescue references an unbound `stderr` local and raises `NameError`,
masking the original error. Hard to trigger in practice (capture3 rarely
raises) but the code is wrong as written.
**Recommended fix**: capture into a local initialised to `nil` outside the
begin block, or move the rescue into a separate begin/rescue around just
the Open3 call.

### Two iOS lanes + two Android lanes mutate state without summary boxes (CLAUDE.md §5.1)
**Files**:
- `fastlane/ios/Fastfile:638` — `upload_metadata_promotion_whats_news` calls `deliver(...)` then returns; no summary box.
- `fastlane/android/Fastfile:391` — `update_metadata` calls `supply(...)` then returns; no summary box.
- `fastlane/android/Fastfile:433` — `download_store_listing` ends with `UI.success(...)`; no summary box.
- `fastlane/ios/Fastfile:256` — `deploy_testflight` is a thin alias for `test_flight` (whose summary box covers it). OK as-is.
- `fastlane/ios/Fastfile:306` — `deploy_appstore` is a thin alias for `app_store`. OK as-is.

§5.1 says "Every user-facing lane and every storepilot_bridge command MUST
end with a coloured summary box." Aliases that delegate are fine; lanes
that perform their own delivery / supply / download call are not.
**Recommended fix**: add `FastlaneCliConfig.print_summary_box(...)` at the
end of each of the three flagged lanes. Pattern is established in their
sibling lanes (`download_metadata`, `download_screenshots`, etc.).

### `pubspec.yaml` `name:` regex rejects quoted names
**File**: `fastlane/storepilot_bridge.rb:806-810` (`read_pubspec_app_name`),
`fastlane/Fastfile:142-143`.
**Finding**: `^\s*name:\s*([^\s#]+)\s*$` does not match `name: "my app"`
or `name: 'my_app'`. Most Flutter pubspecs use bare identifiers so this is
benign, but the doc-recommended `name: ...` per YAML spec does allow
quoted scalars. Returns `nil` silently when this happens.
**Recommended fix**: low priority; tolerate optional quotes:
`^\s*name:\s*["']?([A-Za-z0-9_]+)["']?\s*(?:#.*)?$`.

### `bump_flutter_pubspec_build_number` rescues `StandardError` and re-wraps as `BridgeError`
**File**: `fastlane/storepilot_bridge.rb:910-912`.
**Finding**: the `rescue StandardError => e` at the bottom of the method
catches the `BridgeError` raised earlier in the same method (e.g. "version
satiri bulunamadi") and re-wraps it with the prefix "Flutter version
guncellenemedi: ", producing nested messages like
`"Flutter version guncellenemedi: pubspec.yaml icinde version satiri bulunamadi."`
The spec asserts the inner message via `raise_error(BridgeError, /version satiri/)`
which still passes because Regex matches a substring — but the error
message is messier than intended.
**Recommended fix**: change the bottom rescue to
`rescue BridgeError; raise` then `rescue StandardError => e; raise BridgeError, "Flutter version guncellenemedi: #{e.message}"`.

### `fetch_apple_metadata` and `fetch_google_metadata` swallow individual API errors as text-in-`errors` arrays
**File**: `fastlane/storepilot_bridge.rb:184-190, 318-326`.
**Finding**: Both paths catch `StandardError` and append to an `errors`
array on the response, which means callers (Dart side) silently degrade
on partial-failure. That's the intended behaviour for "best-effort store
metadata fetch", but the errors array is currently returned as plain
strings — losing class info and any structured error code. If a caller
ever needs to distinguish "auth failed" from "no localization found" they
can't.
**Recommended fix**: low priority; promote errors to
`{ code, message, source }` shape when a future Dart consumer needs it.

### `fetch_google_play_icon` parses HTML with a regex
**File**: `fastlane/storepilot_bridge.rb:1240`.
**Finding**: scraping Play Store HTML for the `og:image` is inherently
fragile — Google can change the meta tag layout at any time. Wrapped in
`rescue StandardError => nil` so it degrades to "no icon" cleanly, but
silent regressions are possible.
**Recommended fix**: accepted technical debt; consider a small monitoring
ping in CI (run the icon fetch against a couple of well-known package
names monthly and alert on consecutive nils).

### `normalize_google_token_uri` allow-list is hard-coded
**File**: `fastlane/storepilot_bridge.rb:1186-1188`.
**Finding**: the SSRF guard hard-codes `oauth2.googleapis.com` and
`www.googleapis.com`. If Google ever rotates the token endpoint host the
bridge will silently fall back to the default token URI (which is the
intended fail-safe behaviour, but worth a comment).
**Recommended fix**: leave as-is; the fall-through to
`DEFAULT_GOOGLE_TOKEN_URI` is correct. Could log a UI warning when the
host is rejected so misconfiguration is visible.

---

## 🟢 Style / clarity (suggestions only)

### `common_helpers.rb` exposes 50+ module functions
**File**: `fastlane/common_helpers.rb`.
**Finding**: the module has grown to a kitchen-sink utility. A handful of
near-duplicate option-resolution methods (`option_or_env`,
`absolute_option_or_env`, `path_option`, `path_or_default`, `maybe_absolute`)
exist with slightly different semantics. Adding a new caller requires
reading the file to figure out which one to use.
**Suggestion**: a follow-up refactor could fold them into a single
`Resolver` class with `string`, `path`, `absolute_path` modes. Out of
scope for this audit because the surface is widely consumed and a refactor
without behavioural tests on every call site would be risky.

### `storepilot_bridge.rb` mixes Turkish and English in user-facing error messages
**File**: `fastlane/storepilot_bridge.rb` — strings like
`"pubspec.yaml bulunamadi"`, `"Klasor bulunamadi"`, `"map formatinda olmali"`.
**Finding**: bridge error messages surface in the Dart TUI. The repo is
English-first (CLAUDE.md, READMEs) but error strings are Turkish.
**Suggestion**: when the slang i18n work picks up bridge errors, normalise
to English keys and route through `app_texts`. Until then, callers should
not pattern-match on these strings.

### `Open3.capture3("/bin/zsh", "-lc", command, ...)` in `run_shell_command!`
**File**: `fastlane/storepilot_bridge.rb:1077`.
**Finding**: hardcodes `/bin/zsh` and forces a login shell. On a non-macOS
CI box (or one with zsh missing) this will fail. Should fall back to
`/bin/sh` or `ENV['SHELL']`.
**Suggestion**: low priority — bridge is currently only invoked from
macOS via the Dart CLI. Track in ROADMAP if Linux dev support lands.

### `build_development_project` is 80 LOC with three switch arms
**File**: `fastlane/storepilot_bridge.rb:419-496`.
**Finding**: long method; each `case profile[:project_type]` arm could be
extracted into `build_flutter_project`, `build_android_only_project`,
`build_ios_only_project` for readability.
**Suggestion**: refactor when adding the next platform arm (currently 2
of 3 are real).

### Inconsistent fallback build numbers
**Files**: `fastlane/storepilot_bridge.rb:896` (`build_number.to_i <= 0 ? 1 : build_number.to_i + 1`)
vs `fastlane/Fastfile:135` (`[a_build.to_i, i_build.to_i, pubspec_build].max`).
**Finding**: bridge bumps from `0` to `1`; Fastfile takes the max across
sources. Both are correct in context, but the asymmetry is invisible to
callers reading either site in isolation.
**Suggestion**: add a `# Why:` comment at each call site referencing the
other.

### `SUMMARY_BOX_WIDTH = 78` is module-wide constant
**File**: `fastlane/common_helpers.rb:668`.
**Finding**: hard-codes 78 columns. Some lanes pass long paths that wrap
ugly when terminal is narrow. Could auto-detect `IO.console.winsize` and
clamp to `min(78, winsize - 4)`.
**Suggestion**: only worth doing if users complain — most CI logs are
wide enough.

### `materialize_review_information` doesn't differentiate "no defaults dir" from "all defaults empty"
**File**: `fastlane/common_helpers.rb:585-611`.
**Finding**: returns `[]` either way. Caller can't tell the difference
between "feature disabled" and "everything is already present".
**Suggestion**: low value; the call sites currently don't care.

---

## Items NOT testable in this audit

- **`authenticate_apple` / Spaceship::ConnectAPI::Token.create** — requires a real
  App Store Connect API key. Specs stub `Spaceship::ConnectAPI::Token` but
  cannot verify the JWT shape end-to-end.
- **`fetch_google_access_token` / Google::Auth::ServiceAccountCredentials** —
  requires a real service-account JSON. Specs only verify the input payload
  shape via `google_service_account_payload`.
- **`fetch_apple_metadata`, `fetch_google_metadata`** — these orchestrate
  multiple Spaceship/Supply calls and produce shaped output. The shaping
  itself is testable in principle (build fixture doubles for
  `App.get_app_store_versions`, etc.) but every method returns custom
  objects and stubbing the chain accurately is more code than the value
  warrants for a first audit pass. Recommend revisiting if a regression
  is reported.
- **iOS / Android Fastfile lanes** — these invoke `sh(...)` and the real
  `deliver`, `supply`, `pilot` actions. End-to-end testing requires a real
  app + credentials. The pure helpers they depend on (option resolution,
  summary box, identifier resolution) are covered.
- **`google_play_track_releases` action** — thin pass-through over
  `Supply::Client`; would need a Play Console fixture to assert anything
  meaningful.
- **`bin/sync_metadata_fallbacks.rb`** — invokes
  `FastlaneCliConfig::LOCALISED_URL_FALLBACK_FILES` constants + identical
  logic to `materialize_localised_fallbacks`. Covered transitively.

---

## How to run

```bash
cd fastlane
bundle install
bundle exec rspec
```

Test output is documented above. CI integration: a new `ruby_test` job in
`.github/workflows/ci.yml` runs the same command on every push and PR.
