import 'dart:async';

/// Test suite global hooks for the `fastlane_cli` package.
///
/// `fastlane_cli` is a pure-Dart CLI (no Flutter, no widgets, no goldens,
/// no `Equatable` value objects). The canonical Flutter Test Strategy
/// §14.2 template is therefore intentionally empty here: no
/// `TestWidgetsFlutterBinding`, no `LeakTesting`, no `AlchemistConfig`.
///
/// This file exists so the package conforms to the §14 "every package has
/// a `flutter_test_config.dart`" rule and any future shared hooks land in
/// the same canonical location.
///
/// Honoured when the suite is invoked via `flutter test` (which Melos uses
/// repo-wide). It is a no-op under `dart test`, which does not load
/// `flutter_test_config.dart`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
