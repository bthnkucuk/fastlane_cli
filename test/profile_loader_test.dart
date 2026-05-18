import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/profile_loader.dart';
import 'package:fastlane_cli/src/services/runner_resolver.dart';
import 'package:test/test.dart';

/// A [RunnerResolver] that always returns the profile-adjacent `fastlane/`
/// directory (created by the test fixtures). Lets profile-loader tests assert
/// loader behaviour without depending on the host's real fastlane runner being
/// discoverable via [Platform.resolvedExecutable] or `Isolate.resolvePackageUri`.
class _FakeRunnerResolver extends RunnerResolver {
  _FakeRunnerResolver(this._fastlaneDir);

  final String _fastlaneDir;

  @override
  Future<String> resolve({String? profileOverride}) async {
    if (profileOverride != null && profileOverride.trim().isNotEmpty) {
      return profileOverride;
    }
    return _fastlaneDir;
  }
}

/// Creates the supplied `fastlane/` directory and seeds an empty `Fastfile`
/// so the real [RunnerResolver] also accepts it as a valid runner.
Directory _seedFastlaneDir(String path) {
  final dir = Directory(path)..createSync(recursive: true);
  File('${dir.path}/Fastfile').writeAsStringSync('# stub');
  return dir;
}

void main() {
  group('ProfileLoader', () {
    test('parses valid profile and resolves app root', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile',
      );
      addTearDown(() => temp.delete(recursive: true));

      final appRoot = Directory('${temp.path}/app')
        ..createSync(recursive: true);
      final fastlaneDir = _seedFastlaneDir('${appRoot.path}/fastlane');
      final profileFile = File('${fastlaneDir.path}/cli_profile.yaml')
        ..writeAsStringSync(_validProfileYaml);

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(fastlaneDir.path),
      );
      final profile = await loader.load(profileFile.path);

      expect(profile.appName, 'ExampleApp');
      expect(profile.appRootPath, appRoot.path);
      expect(profile.fastlaneDirectoryPath, '${appRoot.path}/fastlane');
      expect(profile.fastlaneRunnerDirectoryPath, '${appRoot.path}/fastlane');
      expect(
        profile.actionsById.containsKey('android_update_metadata'),
        isTrue,
      );
      expect(profile.shortcutActionIds, contains('android_update_metadata'));
      expect(
        profile
            .actionsById['android_update_metadata']!
            .requiresOverwriteConfirmation,
        isTrue,
      );
    });

    test('throws when profile file is missing', () async {
      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver('/tmp'),
      );
      expect(
        () => loader.load('/nonexistent/path/cli_profile.yaml'),
        throwsA(
          predicate<FormatException>(
            (e) => e.message.contains('Profile not found'),
          ),
        ),
      );
    });

    test('throws when root is not a YAML map', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile_scalar',
      );
      addTearDown(() => temp.delete(recursive: true));

      final profileFile = File('${temp.path}/cli_profile.yaml')
        ..writeAsStringSync('just a string');

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(temp.path),
      );
      expect(
        () => loader.load(profileFile.path),
        throwsA(
          predicate<FormatException>(
            (e) => e.message.contains('Profile must be a YAML map'),
          ),
        ),
      );
    });

    test('throws when shortcut references unknown action', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile_shortcut',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fastlaneDir = _seedFastlaneDir('${temp.path}/fastlane');
      final profileFile = File('${temp.path}/cli_profile.yaml')
        ..writeAsStringSync(_shortcutInvalidYaml);

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(fastlaneDir.path),
      );
      expect(() => loader.load(profileFile.path), throwsFormatException);
    });

    test('throws when categories is not a list', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile_list',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fastlaneDir = _seedFastlaneDir('${temp.path}/fastlane');
      final profileFile = File('${temp.path}/cli_profile.yaml')
        ..writeAsStringSync(_categoriesNotListYaml);

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(fastlaneDir.path),
      );
      expect(() => loader.load(profileFile.path), throwsFormatException);
    });

    test('skips merge when base profile is not a map', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile_bad_base',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fastlaneDir = _seedFastlaneDir('${temp.path}/fastlane');
      File('${fastlaneDir.path}/cli_profile.base.yaml').writeAsStringSync(
        'not_a_map',
      );
      File('${temp.path}/cli_profile.yaml').writeAsStringSync(
        _overlayOnlyProfileYaml,
      );

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(fastlaneDir.path),
      );
      final profile = await loader.load('${temp.path}/cli_profile.yaml');

      expect(profile.actionsById.containsKey('only_here'), isTrue);
    });

    test('merges cli_profile.base.yaml over actions and categories', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile_merge',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fastlaneDir = _seedFastlaneDir('${temp.path}/fastlane');
      File('${fastlaneDir.path}/cli_profile.base.yaml').writeAsStringSync(
        _baseProfileYaml,
      );
      File('${temp.path}/cli_profile.yaml').writeAsStringSync(_overlayMergeYaml);

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(fastlaneDir.path),
      );
      final profile = await loader.load('${temp.path}/cli_profile.yaml');

      expect(profile.appName, 'OverlayApp');
      final action = profile.actionsById['shared_action']!;
      expect(action.title[LocaleCode.en], 'Overridden Title');
    });

    test('parses plain string category title', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile_str_title',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fastlaneDir = _seedFastlaneDir('${temp.path}/fastlane');
      final profileFile = File('${temp.path}/cli_profile.yaml')
        ..writeAsStringSync(_plainTitleCategoryYaml);

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(fastlaneDir.path),
      );
      final profile = await loader.load(profileFile.path);

      expect(profile.categories.single.title[LocaleCode.tr], 'Plain');
      expect(profile.categories.single.title[LocaleCode.en], 'Plain');
    });

    test('parses string boolean flags in YAML', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile_bool',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fastlaneDir = _seedFastlaneDir('${temp.path}/fastlane');
      final profileFile = File('${temp.path}/cli_profile.yaml')
        ..writeAsStringSync(_stringBoolYaml);

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(fastlaneDir.path),
      );
      final profile = await loader.load(profileFile.path);

      final action = profile.actionsById['str_bool']!;
      expect(action.shortcut, isTrue);
      expect(action.requiresConfirmation, isFalse);
    });

    test('throws when category mapping is invalid', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_profile_invalid',
      );
      addTearDown(() => temp.delete(recursive: true));

      final fastlaneDir = _seedFastlaneDir('${temp.path}/fastlane');
      final profileFile = File('${temp.path}/cli_profile.yaml')
        ..writeAsStringSync(_invalidProfileYaml);

      final loader = ProfileLoader(
        runnerResolver: _FakeRunnerResolver(fastlaneDir.path),
      );
      expect(
        () => loader.load(profileFile.path),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

const String _validProfileYaml = '''
app:
  name: ExampleApp
  root_path: ..
  fastlane_path: fastlane
  default_locale: tr
  supported_locales: [tr, en]
shortcuts:
  - android_update_metadata
categories:
  - id: android
    title:
      tr: Android
      en: Android
    actions:
      - android_update_metadata
actions:
  - id: android_update_metadata
    category: android
    title:
      tr: Android metadata
      en: Android metadata
    preflight:
      - android_metadata
    shortcut: true
    requires_overwrite_confirmation: true
    command:
      type: fastlane
      platform: android
      lane: update_metadata
''';

const String _invalidProfileYaml = '''
app:
  name: ExampleApp
  root_path: .
categories:
  - id: android
    title: Android
    actions:
      - missing_action
actions:
  - id: action_1
    category: unknown_category
    title: Action
    command:
      type: fastlane
      lane: version_status
''';

const String _shortcutInvalidYaml = '''
app:
  name: ExampleApp
  root_path: .
categories:
  - id: android
    title: Android
    actions:
      - a1
actions:
  - id: a1
    category: android
    title: Action
    command:
      type: fastlane
      lane: noop
shortcuts:
  - missing_shortcut
''';

const String _baseProfileYaml = '''
app:
  name: BaseApp
  root_path: .
categories:
  - id: android
    title:
      tr: Base Cat
      en: Base Cat
    actions:
      - shared_action
actions:
  - id: shared_action
    category: android
    title:
      tr: Base Title
      en: Base Title
    command:
      type: fastlane
      lane: noop
''';

const String _overlayOnlyProfileYaml = '''
app:
  name: Solo
  root_path: .
categories:
  - id: android
    title:
      tr: A
      en: A
    actions:
      - only_here
actions:
  - id: only_here
    category: android
    title:
      tr: T
      en: T
    command:
      type: fastlane
      lane: noop
''';

const String _plainTitleCategoryYaml = '''
app:
  name: App
  root_path: .
categories:
  - id: c
    title: Plain
    actions:
      - a1
actions:
  - id: a1
    category: c
    title:
      tr: T
      en: T
    command:
      type: flutter
      args: []
''';

const String _stringBoolYaml = '''
app:
  name: App
  root_path: .
categories:
  - id: c
    title:
      tr: C
      en: C
    actions:
      - str_bool
actions:
  - id: str_bool
    category: c
    title:
      tr: T
      en: T
    shortcut: "true"
    requires_confirmation: "false"
    command:
      type: flutter
      args: []
''';

const String _categoriesNotListYaml = '''
app:
  name: ExampleApp
  root_path: .
categories: "oops"
actions: []
''';

const String _overlayMergeYaml = '''
app:
  name: OverlayApp
  root_path: .
categories:
  - id: android
    title:
      tr: Overlay Cat
      en: Overlay Cat
    actions:
      - shared_action
actions:
  - id: shared_action
    category: android
    title:
      tr: Overridden Title
      en: Overridden Title
    command:
      type: fastlane
      platform: android
      lane: noop
''';
