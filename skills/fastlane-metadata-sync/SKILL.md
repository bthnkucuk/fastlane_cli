---
name: fastlane-metadata-sync
description: Pull or push store metadata (titles, descriptions, release notes, screenshots, App Privacy) between the local `fastlane/metadata/` tree and the App Store / Play Console. Triggers on: metadata, store listing, screenshots, release notes, what's new, description, title, app privacy, nutrition label, push metadata, pull metadata, download listing, upload listing.
---

# fastlane_cli — store metadata sync

Use this skill when the user wants to move store-facing text or imagery
between disk and the App Store / Play Console. Two directions:

- **Download** (remote → local): pulls metadata into the fastlane folder so
  the user can edit / review them in git.
- **Upload** (local → remote): pushes the local fastlane folder contents to
  the store.

Always discover the available action ids with `fastlane_cli list --json
--profile <path>` first — the table below covers the base profile only.

## Android (Google Play)

| Action id                          | Lane (`android`)                | Direction | Notes                                                                                       |
| ---------------------------------- | ------------------------------- | --------- | ------------------------------------------------------------------------------------------- |
| `android_download_store_listing`   | `download_store_listing`        | pull      | Pulls listing for `track: internal` (configurable via profile option). Overwrites local.    |
| `android_update_metadata`          | `update_metadata`               | push      | Pushes text + images + screenshots + changelogs to `track: alpha` (default).                |
| `android_update_metadata_only`     | `update_metadata` (`include_images: "false"`, `include_screenshots: "false"`, `include_changelogs: "false"`) | push | Text-only push (cheap, fast; no media re-upload).                                           |

Credentials: `GOOGLE_PLAY_JSON_KEY_PATH` must point to the service-account
JSON. The action will hard-fail with a clear remediation if it's missing.

Local layout: Play metadata lives under
`$ANDROID_METADATA_PATH` (default: `<fastlane_root>/android/metadata/<locale>/`).
Override via the `ANDROID_METADATA_PATH` / `FASTLANE_ANDROID_METADATA_PATH`
env var if the user keeps it elsewhere.

## iOS (App Store Connect)

| Action id                          | Lane (`ios`)                                  | Direction | Notes                                                                              |
| ---------------------------------- | --------------------------------------------- | --------- | ---------------------------------------------------------------------------------- |
| `ios_download_metadata`            | `download_metadata`                           | pull      | Pulls localized listing + release notes.                                           |
| `ios_download_screenshots`         | `download_screenshots`                        | pull      | Pulls the App Store screenshots into the fastlane folder.                          |
| `ios_update_metadata`              | `update_metadata` (`include_screenshots: "true"`) | push  | Full metadata push including screenshots.                                          |
| `ios_upload_promotional_metadata`  | `upload_metadata_promotion_whats_news` (`include_screenshots: "false"`) | push | Promotion text + What's New only.                                                  |
| `ios_upload_app_privacy`           | `upload_app_privacy_details`                  | push      | Uploads the App Privacy nutrition-label JSON.                                      |
| `ios_download_app_privacy`         | `download_app_privacy_details`                | pull      | Downloads the current App Privacy JSON.                                            |

Credentials: App Store Connect API key, in priority order — see
[CLAUDE.md](../../CLAUDE.md) §5.3:

1. `APP_STORE_CONNECT_API_KEY_JSON_PATH`, or
2. `APP_STORE_CONNECT_API_KEY_ID` + `_ISSUER_ID` + `_FILEPATH` (`.p8`).

Local layout: iOS metadata under
`$IOS_METADATA_PATH` (default: `<fastlane_root>/ios/metadata/<locale>/`),
screenshots under `$IOS_SCREENSHOTS_PATH`, promotional metadata under
`$IOS_PROMOTION_METADATA_PATH`. Use the matching `FASTLANE_*` aliases too.

## Confirm before destructive pulls

The `*_download_*` and `*_download_store_listing` actions are flagged
`requires_overwrite_confirmation: true` — they overwrite local files that may
not be in git yet. Before running, advise the user to:

1. Commit / stash current `fastlane/metadata/` and `fastlane/screenshots/`.
2. Run the download.
3. `git diff` to review what changed before re-staging.

## Default templates

`fastlane/ios/defaults/review_information/` (email, first/last name, phone,
demo account) ships with placeholder values. If a per-app profile doesn't
override these, the user must override them in their own
`profile.yaml` or in the `fastlane/metadata/review_information/` files
before any App Store upload.

## Recommended workflow

1. **First sync**: pull both directions (`ios_download_metadata`,
   `ios_download_screenshots`, `android_download_store_listing`) into a
   clean working tree.
2. Commit the baseline.
3. Make text/screenshot edits locally.
4. Push back with `ios_update_metadata` / `android_update_metadata` (or the
   `_only` / `_promotional` variants if the change is text-only).
5. Re-pull and `git diff` after the push to confirm what the store now reflects
   (the store may normalize whitespace or reject fields).

## Do not

- Push `update_metadata` against `track: production` from a per-app profile
  without confirming with the user — the base profile pins it to `alpha`.
- Upload an `App Privacy` JSON without first running `ios_download_app_privacy`
  to see the current state; this avoids accidentally clearing a category.
- Edit files under `fastlane/ios/defaults/` for app-specific content — those
  are repo-wide template defaults; app overrides belong in the consumer's
  fastlane folder.
