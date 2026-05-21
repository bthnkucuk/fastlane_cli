/// Generic, brand-free `profile.yaml` fixture strings for the end-to-end
/// pipeline tests in `test/e2e/`.
///
/// Every value here is a placeholder — `MyApp`, `com.example.myapp`, and the
/// `dev` / `staging` / `prod` flavor triple. Nothing references a real app
/// (CLAUDE.md §5.2). These strings are materialised onto a tmp filesystem by
/// the e2e harness so the *real* `ProfileResolver` → `ProfileLoader` →
/// `CommandBuilder` chain runs against an on-disk profile.
library;

/// A full per-app profile that exercises the whole feature surface the e2e
/// tests assert on:
///  - an `app:` block carrying `package_name` / `bundle_id` identity (the
///    lowest-precedence option layer),
///  - a top-level `default_options:` block (sits above `app:` identity),
///  - a plain fastlane action that inherits every default verbatim,
///  - a fastlane action whose own `command.options` override one default,
///  - a `flutter` action (carries no options — defaults must NOT leak in),
///  - shortcuts + categories so profile-consistency validation runs.
///
/// `root_path` / `fastlane_runner_path` are intentionally relative so the
/// harness can drop this file anywhere and have the loader resolve paths
/// against the profile directory.
const String fullProfileYaml = '''
app:
  name: MyApp
  root_path: .
  fastlane_path: fastlane
  fastlane_runner_path: fastlane
  default_locale: en
  supported_locales: [en, tr]
  package_name: com.example.myapp
  bundle_id: com.example.myapp.ios

default_options:
  flavor: dev
  target: lib/main_dev.dart
  obfuscate: "false"

shortcuts:
  - android_internal
  - ios_testflight

categories:
  - id: android
    title:
      tr: Android
      en: Android
    actions:
      - android_internal
      - android_production
  - id: ios
    title:
      tr: iOS
      en: iOS
    actions:
      - ios_testflight
  - id: general
    title:
      tr: Genel
      en: General
    actions:
      - run_tests

actions:
  - id: android_internal
    category: android
    title:
      tr: Android internal
      en: Android internal
    shortcut: true
    command:
      type: fastlane
      platform: android
      lane: internal_testing

  - id: android_production
    category: android
    title:
      tr: Android production
      en: Android production
    requires_confirmation: true
    command:
      type: fastlane
      platform: android
      lane: production
      options:
        flavor: prod
        target: lib/main_prod.dart
        upload_symbols: "true"

  - id: ios_testflight
    category: ios
    title:
      tr: iOS TestFlight
      en: iOS TestFlight
    shortcut: true
    command:
      type: fastlane
      platform: ios
      lane: test_flight
      options:
        flavor: staging

  - id: run_tests
    category: general
    title:
      tr: Testler
      en: Tests
    command:
      type: flutter
      args:
        - test
''';

/// A minimal per-app overlay that relies on `profile.base.yaml` for every
/// category/action — used to prove base-merge happens during e2e discovery.
/// It overrides the base `android_internal` lane to demonstrate merge-by-id.
const String overlayProfileYaml = '''
app:
  name: MyApp
  root_path: .
  fastlane_path: fastlane
  fastlane_runner_path: fastlane

default_options:
  flavor: staging

actions:
  - id: android_internal
    category: android
    title:
      tr: Android internal (overlay)
      en: Android internal (overlay)
    command:
      type: fastlane
      platform: android
      lane: internal_testing
      options:
        track: beta
''';

/// The shared base profile that [overlayProfileYaml] merges on top of. Mirrors
/// the shape of the repo's real `fastlane/profile.base.yaml` but trimmed to
/// what the e2e merge test needs.
const String baseProfileYaml = '''
default_locale: en
supported_locales: [en, tr]

default_options:
  region: us
  flavor: dev

categories:
  - id: android
    title:
      tr: Android
      en: Android
    actions:
      - android_internal

actions:
  - id: android_internal
    category: android
    title:
      tr: Base android internal
      en: Base android internal
    command:
      type: fastlane
      platform: android
      lane: internal_testing
''';

/// A profile whose `default_options` block ALSO carries a `package_name` /
/// `app_identifier` — proving `default_options` outranks the `app:` block
/// identity on key collision (precedence: app identity < default_options).
const String identityOverriddenByDefaultOptionsYaml = '''
app:
  name: MyApp
  root_path: .
  fastlane_runner_path: fastlane
  package_name: com.example.appblock
  bundle_id: com.example.appblock.ios

default_options:
  package_name: com.example.defaultopts
  app_identifier: com.example.defaultopts.ios

categories:
  - id: android
    title:
      tr: Android
      en: Android
    actions:
      - android_ship
actions:
  - id: android_ship
    category: android
    title:
      tr: Ship
      en: Ship
    command:
      type: fastlane
      platform: android
      lane: internal_testing
''';

/// A profile whose per-action `command.options` carries `package_name` —
/// proving a per-action option outranks BOTH the `app:` block identity and
/// `default_options` on key collision.
const String identityOverriddenByActionOptionsYaml = '''
app:
  name: MyApp
  root_path: .
  fastlane_runner_path: fastlane
  package_name: com.example.appblock
  bundle_id: com.example.appblock.ios

categories:
  - id: android
    title:
      tr: Android
      en: Android
    actions:
      - android_ship
actions:
  - id: android_ship
    category: android
    title:
      tr: Ship
      en: Ship
    command:
      type: fastlane
      platform: android
      lane: internal_testing
      options:
        package_name: com.example.actionopts
''';

/// Syntactically broken YAML — unbalanced brackets — to drive the
/// malformed-profile failure path.
const String malformedProfileYaml = '''
app:
  name: MyApp
  root_path: .
categories: [ this is : not valid ]]]
actions:
''';

/// Structurally valid YAML that violates a profile invariant: the action's
/// `category` points at a category id that does not exist. The loader must
/// reject this with a [FormatException].
const String inconsistentProfileYaml = '''
app:
  name: MyApp
  root_path: .
  fastlane_runner_path: fastlane
categories:
  - id: android
    title:
      tr: Android
      en: Android
    actions:
      - orphan
actions:
  - id: orphan
    category: does_not_exist
    title:
      tr: Orphan
      en: Orphan
    command:
      type: fastlane
      platform: android
      lane: noop
''';
