---
name: fastlane-play-store-setup
description: Automate the Google Play Console "Set up your app" checklist for a new Android app via fastlane_cli — store listing, contact details, and the Data safety form in one confirmed run, plus the explicit manual remainder. Triggers on: store setup, set up your app, play console setup, app content, data safety, contact details, store listing checklist, android_store_setup, android_update_app_details, android_upload_data_safety, production checklist, yeni uygulama kurulumu.
---

# fastlane_cli — Play Console "Set up your app" flow

Use this skill when the user has a **new (or incompletely set up) Android app
in Play Console** and wants to clear the "Set up your app" checklist that
blocks production releases. The Play Developer API only covers part of that
checklist — these actions automate everything the API reaches and print an
explicit checklist of what stays manual.

## Prerequisites

1. **The app record must already exist in Play Console.** Creating the app
   record itself has no API — someone must have clicked "Create app" once.
2. **Service-account key with app-content permissions:**

   ```sh
   export GOOGLE_PLAY_JSON_KEY_PATH="/abs/path/to/play-service-account.json"
   ```

   Release-manager alone is not enough for contact details / Data safety —
   the account needs store-settings / app-content level access (Play Console
   → Users and permissions). A 403 from these lanes almost always means a
   missing permission there.
3. **Package name** — `app.package_name` in `profile.yaml` or
   `ANDROID_PACKAGE_NAME` / `FASTLANE_APP_IDENTIFIER` env (same resolution
   as every other Android lane; see `fastlane-play-internal`).

## Choose the action

Discover the live set with `fastlane_cli list --json --profile <path>`
first, then pick from these base actions (all in the `android` category):

| Action id                    | Lane (`android`)     | Confirms? | Use when                                                                 |
| ---------------------------- | -------------------- | --------- | ------------------------------------------------------------------------ |
| `android_store_setup`        | `store_setup`        | yes       | One-shot setup of a fresh app: listing + contact details + Data safety.  |
| `android_update_app_details` | `update_app_details` | no        | Only the contact details / default language changed. Idempotent.         |
| `android_upload_data_safety` | `upload_data_safety` | yes       | Only the Data safety form. **Replaces the ENTIRE form** — see warnings.  |

### `android_store_setup` (composite)

Runs three steps in order, then ALWAYS prints one final summary box:

1. **Store listing** — delegates in-process to the existing
   `update_metadata` lane when `<metadata_path>` contains locale
   directories. Base-profile defaults: `track: alpha`,
   `include_images: "true"`, `include_screenshots: "true"`, and
   `include_changelogs: "false"` — changelogs need an existing release,
   which a brand-new app does not have. On a **brand-new app the track has
   no release yet**, so supply rejects the image/screenshot push with a
   "release/track not ready" error. The composite treats that as a normal
   **not-ready condition and soft-skips** (`atlandı (track'te henüz release
   yok …)`) — it is NOT a failure. Upload a build first; the listing is
   delivered together with that first release.
2. **Contact details** — via the `google_play_app_details` custom action,
   only when at least one field resolves (see value sources below).
3. **Data safety** — via the `google_play_data_safety` custom action, but
   **only when a USER-provided CSV resolves** (option / `ANDROID_DATA_SAFETY_CSV_PATH`
   env / app `<fastlane_root>/android/data_safety.csv`). The generic
   CLI-default template is **NEVER auto-uploaded** — Google rejects it (400)
   and pushing it would overwrite a real form with generic answers. When only
   the template (or nothing) resolves, the step **soft-skips** (`atlandı
   (kendi data_safety.csv'ni ver …)`).

Failure semantics (important when reading the output back to the user):

- A step with **missing inputs** soft-skips with an `atlandı (…)` marker —
  the lane keeps going and still exits 0 if nothing actually failed.
- A step that was **attempted and raised** records a `hata (…)` marker; the
  remaining steps still run, the final box still prints, and only then the
  lane fails (`user_error!`) — so a setup lane never exits 0 on a real API
  failure, but you always see which steps landed.
- The final box ends with the 9-item **manual checklist** (below) and the
  precondition note that the app record must already exist.

### `android_update_app_details` (granular)

Contact email / phone / website + default language via `edits.details`.
GET-diff-PATCH: the lane reads the current values from Play and **only
writes the fields that actually changed** (no-op commit-free run when Play
is already current). **Hard-fails** when no field resolves from any source —
a no-op contact update is useless, so the error names every source it tried.
`default_language` is validated against the listing's existing locales
before it is sent. Supports `validate_only: "true"` (validate + abort, no
commit).

### `android_upload_data_safety` (granular)

Uploads the Data safety CSV. **The POST replaces the ENTIRE form and the
API has no read/pull counterpart** — there is no way to download the current
form first, so an accidental upload is unrecoverable. That is why the action
is `requires_confirmation: true` and the summary box always names which CSV
source was used ("app override" vs "CLI default şablon").

**Requires a user-provided CSV.** If only the bundled generic CLI-default
template resolves, the lane **hard-fails** and tells the user to export their
own form (Play Console → App content → Data safety → Export) to
`<fastlane_root>/android/data_safety.csv`. To knowingly upload the bundled
reference template anyway, pass `data_safety_allow_default:true` (default
`false`). A missing template (nothing resolves at all) still hard-fails as
before.

## Value sources

### Contact details (per field, first hit wins)

| Field              | 1. option          | 2. env                     | 3. metadata-ROOT file  |
| ------------------ | ------------------ | -------------------------- | ---------------------- |
| `contact_email`    | `contact_email`    | `ANDROID_CONTACT_EMAIL`    | `contactEmail.txt`     |
| `contact_phone`    | `contact_phone`    | `ANDROID_CONTACT_PHONE`    | `contactPhone.txt`     |
| `contact_website`  | `contact_website`  | `ANDROID_CONTACT_WEBSITE`  | `contactWebsite.txt`   |
| `default_language` | `default_language` | `ANDROID_DEFAULT_LANGUAGE` | `defaultLanguage.txt`  |

The files live at the **metadata root** (default
`<fastlane_root>/android/metadata/`, next to the locale folders — NOT inside
one). supply only reads locale *directories*, so these root-level files are
invisible to the listing upload. `android_download_store_listing` **pulls**
the current Play values into these files after every listing download
(best-effort — a contact-details failure never breaks the download), so a
pull → edit → `android_update_app_details` round-trip works.

### Data safety CSV (ladder — first hit wins)

1. `data_safety_csv_path` option
2. `ANDROID_DATA_SAFETY_CSV_PATH` env
3. app override at `<fastlane_root>/android/data_safety.csv`
4. CLI default template (`android/defaults/data_safety.csv` in the bundled
   runner)

**The app override always wins over the CLI template.** There is **NO
metadata-root tier** for the CSV — a `data_safety.csv` dropped next to
`contactEmail.txt` is silently ignored.

Only tiers 1–3 count as a **user-provided** CSV. The tier-4 CLI-default
template is an **opt-in reference only — it is NEVER auto-uploaded**:

- `android_store_setup` (composite) **soft-skips** the Data safety step when
  only the template (or nothing) resolves — it uploads nothing unless a
  user CSV is provided.
- `android_upload_data_safety` (standalone) **hard-fails** when only the
  template resolves, unless the caller passes `data_safety_allow_default:true`
  to knowingly use it.

Why: Google rejects the generic template with a **400**, and auto-pushing it
would overwrite a hand-filled form with generic answers (whole-form
replacement, no read counterpart to recover from).

The CLI default template carries conservative typical
Flutter + Firebase (Crashlytics) answers: collects **crash logs +
diagnostics only**, collected not shared, encrypted in transit, collection
required, purpose Analytics. To use it, the user should **export their own**
CSV instead: fill the form once in Play Console → **App content → Data safety
→ Export to CSV**, and save it as `<fastlane_root>/android/data_safety.csv`
(or point `data_safety_csv_path` / `ANDROID_DATA_SAFETY_CSV_PATH` at it).

## Capability matrix — automated vs manual

| Play Console item                                             | Automated?  | Mechanism                          |
| ------------------------------------------------------------- | ----------- | ---------------------------------- |
| Store listing (text, graphics, screenshots)                   | ✅          | `update_metadata` (supply)         |
| Contact details + default language                            | ✅          | `google_play_app_details` action   |
| Data safety form                                              | ✅ *(user CSV only)* | `google_play_data_safety` action — needs a user-provided CSV; the generic template is never auto-uploaded |
| **Privacy policy URL**                                        | ❌ manual   | **No API anywhere** — it is not in the Data safety CSV and has no Play Developer API endpoint. Cannot be automated; it is listed FIRST in the checklist because users expect otherwise. |
| App access (test credentials)                                 | ❌ manual   | Console only                       |
| Ads declaration                                               | ❌ manual   | Console only                       |
| Content rating questionnaire                                  | ❌ manual   | Console only                       |
| Target audience                                               | ❌ manual   | Console only                       |
| Government apps declaration                                   | ❌ manual   | Console only                       |
| Financial features declaration                                | ❌ manual   | Console only                       |
| Health declaration                                            | ❌ manual   | Console only                       |
| App category                                                  | ❌ manual   | Console only                       |

`store_setup`'s final summary box prints these 9 manual items so the user
can finish the checklist in the Console without hunting for what is left.

## Invocation

```sh
# One-shot setup (preview the materialized command first):
fastlane_cli run android_store_setup --profile <path> --dry-run
fastlane_cli run android_store_setup --profile <path>

# Granular runs:
fastlane_cli run android_update_app_details --profile <path>
fastlane_cli run android_upload_data_safety --profile <path>

# Override a single field for one run (repeatable; separator is `=`):
fastlane_cli run android_update_app_details --profile <path> \
  --option contact_email=dev@example.com \
  --option default_language=en-US
```

`--profile` is optional when the profile is discoverable by walk-up.

## Do not

- Expect `android_store_setup`/`android_upload_data_safety` to push the
  bundled generic template — it never does. The composite soft-skips Data
  safety unless a user CSV (option / `ANDROID_DATA_SAFETY_CSV_PATH` env / app
  `<fastlane_root>/android/data_safety.csv`) is provided; the standalone lane
  hard-fails on the template unless `data_safety_allow_default:true`. Export
  the app's own CSV first (Play Console → App content → Data safety → Export).
- Pass `data_safety_allow_default:true` to `android_upload_data_safety`
  against an app whose Data safety form was hand-filled in the Console — the
  upload replaces the whole form with the generic template and cannot be
  pulled back.
- Treat the composite's `atlandı (track'te henüz release yok …)` listing
  marker as a failure — it is a normal soft-skip on a brand-new app. Upload a
  build first; the listing rides along with the first release.
- Put `data_safety.csv` at the metadata root — the CSV has no metadata-root
  tier; it belongs at `<fastlane_root>/android/data_safety.csv`.
- Promise privacy-policy automation — the URL has no API anywhere and must
  be entered in the Console by hand.
- Edit the bundled `android/defaults/data_safety.csv` for one app's needs —
  that file is the repo-wide generic template; app-specific answers belong
  in the consumer's `<fastlane_root>/android/data_safety.csv` override.
- Skip the confirmation prompts by scripting around them — both
  confirmation-gated actions are gated precisely because they mutate
  store-facing state that is hard (Data safety: impossible) to restore.
