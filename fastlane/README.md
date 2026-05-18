fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### get_version_data

```sh
[bundle exec] fastlane get_version_data
```

Get Android + iOS versions and return version|build

### internal_test

```sh
[bundle exec] fastlane internal_test
```

Bump app version and trigger platform lanes

### firebase_distribute

```sh
[bundle exec] fastlane firebase_distribute
```

Build and distribute to Firebase App Distribution

----


## Android

### android firebase_distribute

```sh
[bundle exec] fastlane android firebase_distribute
```

Build and distribute Android app to Firebase App Distribution

### android internal_testing

```sh
[bundle exec] fastlane android internal_testing
```

Build and deploy Android app to Google Play internal testing

### android production

```sh
[bundle exec] fastlane android production
```

Build and deploy Android app to Google Play production

### android build_apk

```sh
[bundle exec] fastlane android build_apk
```

Build APK for local testing

### android increment_version

```sh
[bundle exec] fastlane android increment_version
```

Increment version code manually

### android version_status

```sh
[bundle exec] fastlane android version_status
```

Check current version status

### android get_android_version_data

```sh
[bundle exec] fastlane android get_android_version_data
```

Print latest Google Play version and build number as version|buildnumber

### android google_play_help

```sh
[bundle exec] fastlane android google_play_help
```

Instructions for fixing Google Play Console issues

### android update_metadata

```sh
[bundle exec] fastlane android update_metadata
```

Upload Android Play Store metadata (optionally images/screenshots/changelogs)

### android download_store_listing

```sh
[bundle exec] fastlane android download_store_listing
```

Download Android Play Store listing assets (metadata, screenshots, changelogs)

----


## iOS

### ios get_ios_version_data

```sh
[bundle exec] fastlane ios get_ios_version_data
```

Print latest TestFlight version and build number as version|buildnumber

### ios firebase_distribute

```sh
[bundle exec] fastlane ios firebase_distribute
```

Build and distribute iOS app to Firebase App Distribution

### ios test_flight

```sh
[bundle exec] fastlane ios test_flight
```

Upload iOS build to TestFlight

### ios deploy_testflight

```sh
[bundle exec] fastlane ios deploy_testflight
```

Alias for test_flight for backward compatibility

### ios app_store

```sh
[bundle exec] fastlane ios app_store
```

Upload iOS build to App Store Connect

### ios deploy_appstore

```sh
[bundle exec] fastlane ios deploy_appstore
```

Alias for app_store for backward compatibility

### ios upload_dsyms

```sh
[bundle exec] fastlane ios upload_dsyms
```

Upload iOS dSYMs to Firebase Crashlytics

### ios update_metadata

```sh
[bundle exec] fastlane ios update_metadata
```

Upload iOS App Store metadata (optionally screenshots)

### ios upload_app_privacy_details

```sh
[bundle exec] fastlane ios upload_app_privacy_details
```

Upload App Privacy Details (Apple's privacy nutrition label) to App Store Connect

### ios download_app_privacy_details

```sh
[bundle exec] fastlane ios download_app_privacy_details
```

Download current App Privacy Details JSON from App Store Connect

### ios upload_metadata_promotion_whats_news

```sh
[bundle exec] fastlane ios upload_metadata_promotion_whats_news
```

Upload iOS promotional metadata (what's new / promo text)

### ios download_metadata

```sh
[bundle exec] fastlane ios download_metadata
```

Download App Store metadata into fastlane path

### ios download_screenshots

```sh
[bundle exec] fastlane ios download_screenshots
```

Download App Store screenshots into fastlane path

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
