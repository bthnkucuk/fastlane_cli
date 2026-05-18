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
        title: const <AppLocale, String>{
          AppLocale.tr: 'Durum',
          AppLocale.en: 'Status',
        },
        description: const <AppLocale, String>{},
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

      final builder = const CommandBuilder(
        bundleCache: _testBundleCache,
        environment: <String, String>{},
      );
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
        title: const <AppLocale, String>{
          AppLocale.tr: 'Test',
          AppLocale.en: 'Test',
        },
        description: const <AppLocale, String>{},
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
        title: const <AppLocale, String>{
          AppLocale.tr: 'Run',
          AppLocale.en: 'Run',
        },
        description: const <AppLocale, String>{},
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
        title: const <AppLocale, String>{
          AppLocale.tr: 'C',
          AppLocale.en: 'C',
        },
        description: const <AppLocale, String>{},
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
        title: const <AppLocale, String>{
          AppLocale.tr: 'C',
          AppLocale.en: 'C',
        },
        description: const <AppLocale, String>{},
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
        title: const <AppLocale, String>{
          AppLocale.tr: 'N',
          AppLocale.en: 'N',
        },
        description: const <AppLocale, String>{},
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

      final request = const CommandBuilder(
        bundleCache: _testBundleCache,
        environment: <String, String>{},
      ).build(profile: profile, action: action);

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
        title: const <AppLocale, String>{
          AppLocale.tr: 'E',
          AppLocale.en: 'E',
        },
        description: const <AppLocale, String>{},
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

      final request = const CommandBuilder(
        bundleCache: _testBundleCache,
        environment: <String, String>{},
      ).build(profile: profile, action: action);

      expect(request.environment['FOO'], 'bar');
      expect(request.environment['QUOTED'], 'baz');
      expect(request.environment['BUNDLE_PATH'], _expectedBundlePath);
    });

    test(
        'merges app-root/.env, fastlane/.env, and FASTLANE_FLAVOR-scoped env',
        () async {
      final temp = await Directory.systemTemp
          .createTemp('fastlane_cli_dotenv_merge');
      addTearDown(() => temp.delete(recursive: true));

      File(p.join(temp.path, 'fastlane', 'Gemfile'))
        ..createSync(recursive: true)
        ..writeAsStringSync('source "https://rubygems.org"');

      File(p.join(temp.path, '.env')).writeAsStringSync(
        'ROOT_ONLY=root\n'
        'OVERRIDE_ME=fromroot\n'
        'TOWERED=bottom\n',
      );
      File(p.join(temp.path, 'fastlane', '.env')).writeAsStringSync(
        'OVERRIDE_ME=fromfastlane\n'
        'TOWERED=middle\n'
        'FASTLANE_ONLY=fl\n',
      );
      File(p.join(temp.path, 'fastlane', '.env.dev')).writeAsStringSync(
        'TOWERED=top\n'
        'FLAVOR_KEY=devvalue\n',
      );

      final action = CliAction(
        id: 'env_lane',
        categoryId: 'general',
        title: const <AppLocale, String>{
          AppLocale.tr: 'E',
          AppLocale.en: 'E',
        },
        description: const <AppLocale, String>{},
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

      final request = CommandBuilder(
        bundleCache: _testBundleCache,
        environment: const <String, String>{
          'FASTLANE_FLAVOR': 'dev',
          // Shell wins for OVERRIDE_ME because it's defined in some file.
          'OVERRIDE_ME': 'fromshell',
        },
      ).build(profile: profile, action: action);

      // Precedence: shell > fastlane/.env.<flavor> > fastlane/.env > app/.env.
      expect(request.environment['ROOT_ONLY'], 'root');
      expect(request.environment['FASTLANE_ONLY'], 'fl');
      expect(request.environment['FLAVOR_KEY'], 'devvalue');
      expect(request.environment['TOWERED'], 'top');
      expect(request.environment['OVERRIDE_ME'], 'fromshell');
      // Standard plumbing still present.
      expect(request.environment['FASTLANE_ROOT'], '${temp.path}/fastlane');
      expect(request.environment['FASTLANE_APP_ROOT'], temp.path);
    });

    test('throws when fastlane lane is missing', () {
      final action = CliAction(
        id: 'bad_lane',
        categoryId: 'g',
        title: const <AppLocale, String>{
          AppLocale.tr: 'B',
          AppLocale.en: 'B',
        },
        description: const <AppLocale, String>{},
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
