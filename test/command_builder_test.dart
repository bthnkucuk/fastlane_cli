import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/profile_factory.dart';

// Deterministic BundleCache stand-in so tests do not depend on whether the
// host shell exports `RUBY_VERSION` / `XDG_CACHE_HOME` / `HOME`.
const _testBundleCache = BundleCache(
  isMacOS: true,
  isLinux: false,
  environment: <String, String>{
    'HOME': '/Users/test',
    'RUBY_VERSION': '3.2.4',
  },
);
const _expectedBundlePath =
    '/Users/test/Library/Caches/fastlane_cli/bundle/ruby-3.2.4';

void main() {
  group('CommandBuilder', () {
    test('builds fastlane command with bundle gemfile env', () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_builder',
      );
      addTearDown(() => temp.delete(recursive: true));

      final gemfile = File('${temp.path}/fastlane/Gemfile')
        ..createSync(recursive: true)
        ..writeAsStringSync('source "https://rubygems.org"');
      File('${temp.path}/fastlane/Fastfile')
        ..createSync(recursive: true)
        ..writeAsStringSync('lane :noop do; end');

      final action = CliAction(
        id: 'android_version_status',
        categoryId: 'android',
        title: const <LocaleCode, String>{
          LocaleCode.tr: 'Durum',
          LocaleCode.en: 'Status',
        },
        description: const <LocaleCode, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.fastlane,
          platform: 'android',
          lane: 'version_status',
          options: <String, String>{'flavor': 'example'},
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: true,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>[action.id]),
        ],
      );

      final builder = const CommandBuilder(bundleCache: _testBundleCache);
      final request = builder.build(profile: profile, action: action);

      expect(request.executable, 'bundle');
      expect(request.arguments, <String>[
        'exec',
        'fastlane',
        'android',
        'version_status',
        'flavor:example',
      ]);
      expect(request.environment['BUNDLE_GEMFILE'], gemfile.path);
      expect(request.environment['BUNDLE_PATH'], _expectedBundlePath);
      expect(request.environment['FASTLANE_ROOT'], '${temp.path}/fastlane');
      expect(request.workingDirectory, temp.path);
    });

    test('builds fvm flutter command', () {
      final action = CliAction(
        id: 'flutter_test',
        categoryId: 'general',
        title: const <LocaleCode, String>{
          LocaleCode.tr: 'Test',
          LocaleCode.en: 'Test',
        },
        description: const <LocaleCode, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.flutter,
          arguments: <String>['test', '--coverage'],
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      final builder = const CommandBuilder();
      final request = builder.build(profile: profile, action: action);

      expect(request.executable, 'fvm');
      expect(request.arguments, <String>['flutter', 'test', '--coverage']);
    });

    test('builds fvm dart command', () {
      final action = CliAction(
        id: 'dart_script',
        categoryId: 'general',
        title: const <LocaleCode, String>{
          LocaleCode.tr: 'Run',
          LocaleCode.en: 'Run',
        },
        description: const <LocaleCode, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.dart,
          arguments: <String>['run', 'tool.dart'],
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      final request = const CommandBuilder().build(profile: profile, action: action);

      expect(request.executable, 'fvm');
      expect(request.arguments, <String>['dart', 'run', 'tool.dart']);
      expect(request.workingDirectory, '/tmp/app');
    });

    test('builds custom executable command', () {
      final action = CliAction(
        id: 'custom',
        categoryId: 'general',
        title: const <LocaleCode, String>{
          LocaleCode.tr: 'C',
          LocaleCode.en: 'C',
        },
        description: const <LocaleCode, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.custom,
          executable: 'echo',
          arguments: <String>['hello'],
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: '/tmp/z',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      final request = const CommandBuilder().build(profile: profile, action: action);

      expect(request.executable, 'echo');
      expect(request.arguments, <String>['hello']);
    });

    test('throws when custom executable missing', () {
      final action = CliAction(
        id: 'bad_custom',
        categoryId: 'general',
        title: const <LocaleCode, String>{
          LocaleCode.tr: 'C',
          LocaleCode.en: 'C',
        },
        description: const <LocaleCode, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.custom,
          executable: '   ',
          arguments: <String>[],
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: '/tmp/z',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      expect(
        () => const CommandBuilder().build(profile: profile, action: action),
        throwsFormatException,
      );
    });

    test('fastlane omits platform when absent', () async {
      final temp = await Directory.systemTemp.createTemp('fastlane_cli_no_plat');
      addTearDown(() => temp.delete(recursive: true));

      File(p.join(temp.path, 'fastlane', 'Gemfile'))
        ..createSync(recursive: true)
        ..writeAsStringSync('source "https://rubygems.org"');

      final action = CliAction(
        id: 'no_platform',
        categoryId: 'general',
        title: const <LocaleCode, String>{
          LocaleCode.tr: 'N',
          LocaleCode.en: 'N',
        },
        description: const <LocaleCode, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.fastlane,
          lane: 'noop',
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      final request = const CommandBuilder(bundleCache: _testBundleCache)
          .build(profile: profile, action: action);

      expect(request.arguments, <String>['exec', 'fastlane', 'noop']);
      expect(request.environment['BUNDLE_PATH'], _expectedBundlePath);
    });

    test('loads dotenv into environment for fastlane', () async {
      final temp = await Directory.systemTemp.createTemp('fastlane_cli_dotenv');
      addTearDown(() => temp.delete(recursive: true));

      File(p.join(temp.path, 'fastlane', 'Gemfile'))
        ..createSync(recursive: true)
        ..writeAsStringSync('source "https://rubygems.org"');
      File(p.join(temp.path, 'fastlane', '.env')).writeAsStringSync(
        'FOO=bar\n'
        '# comment\n'
        'QUOTED="baz"\n',
      );

      final action = CliAction(
        id: 'env_lane',
        categoryId: 'general',
        title: const <LocaleCode, String>{
          LocaleCode.tr: 'E',
          LocaleCode.en: 'E',
        },
        description: const <LocaleCode, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.fastlane,
          lane: 'noop',
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      final request = const CommandBuilder(bundleCache: _testBundleCache)
          .build(profile: profile, action: action);

      expect(request.environment['FOO'], 'bar');
      expect(request.environment['QUOTED'], 'baz');
      expect(request.environment['BUNDLE_PATH'], _expectedBundlePath);
    });

    test('throws when fastlane lane is missing', () {
      final action = CliAction(
        id: 'bad_lane',
        categoryId: 'g',
        title: const <LocaleCode, String>{
          LocaleCode.tr: 'B',
          LocaleCode.en: 'B',
        },
        description: const <LocaleCode, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.fastlane,
          lane: '',
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: '/tmp',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'g', actionIds: <String>[action.id]),
        ],
      );

      expect(
        () => const CommandBuilder().build(profile: profile, action: action),
        throwsFormatException,
      );
    });
  });
}
