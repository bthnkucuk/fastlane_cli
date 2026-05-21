import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/profile_factory.dart';

void main() {
  group('CommandBuilder', () {
    test('builds fastlane lane invocation against the system fastlane gem',
        () async {
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_builder',
      );
      addTearDown(() => temp.delete(recursive: true));

      // Gemfile is no longer required for fastlane lane invocations — they
      // go through the system / brew `fastlane` gem. The fixture only needs
      // the runner directory and a Fastfile.
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

      final builder = const CommandBuilder(environment: <String, String>{});
      final request = builder.build(profile: profile, action: action);

      expect(request.executable, 'fastlane');
      expect(request.arguments, <String>[
        'android',
        'version_status',
        'flavor:example',
      ]);
      expect(request.environment['FASTLANE_ROOT'], '${temp.path}/fastlane');
      expect(request.workingDirectory, temp.path);
    });

    test(
        'regression — fastlane invocations do NOT carry BUNDLE_GEMFILE / BUNDLE_PATH',
        () async {
      // Without this guarantee the lane spawns `bundle exec fastlane` against
      // the slim storepilot_bridge Gemfile, which exit-7s on every install.
      // See v0.2.1 fix notes.
      final temp = await Directory.systemTemp.createTemp(
        'fastlane_cli_no_bundle_env',
      );
      addTearDown(() => temp.delete(recursive: true));

      File('${temp.path}/fastlane/Fastfile')
        ..createSync(recursive: true)
        ..writeAsStringSync('lane :noop do; end');

      final action = CliAction(
        id: 'ios_release',
        categoryId: 'ios',
        title: const <AppLocale, String>{
          AppLocale.tr: 'R',
          AppLocale.en: 'R',
        },
        description: const <AppLocale, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.fastlane,
          platform: 'ios',
          lane: 'release',
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'ios', actionIds: <String>[action.id]),
        ],
      );

      final request = const CommandBuilder(environment: <String, String>{})
          .build(profile: profile, action: action);

      expect(request.executable, 'fastlane');
      expect(request.environment.containsKey('BUNDLE_GEMFILE'), isFalse);
      expect(request.environment.containsKey('BUNDLE_PATH'), isFalse);
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

      Directory(p.join(temp.path, 'fastlane')).createSync(recursive: true);

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

      final request = const CommandBuilder(environment: <String, String>{})
          .build(profile: profile, action: action);

      expect(request.executable, 'fastlane');
      expect(request.arguments, <String>['noop']);
    });

    test('loads dotenv into environment for fastlane', () async {
      final temp = await Directory.systemTemp.createTemp('fastlane_cli_dotenv');
      addTearDown(() => temp.delete(recursive: true));

      Directory(p.join(temp.path, 'fastlane')).createSync(recursive: true);
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

      final request = const CommandBuilder(environment: <String, String>{})
          .build(profile: profile, action: action);

      expect(request.environment['FOO'], 'bar');
      expect(request.environment['QUOTED'], 'baz');
      expect(request.environment.containsKey('BUNDLE_PATH'), isFalse);
    });

    test(
        'merges app-root/.env, fastlane/.env, and FASTLANE_FLAVOR-scoped env',
        () async {
      final temp = await Directory.systemTemp
          .createTemp('fastlane_cli_dotenv_merge');
      addTearDown(() => temp.delete(recursive: true));

      Directory(p.join(temp.path, 'fastlane')).createSync(recursive: true);

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

      final request = const CommandBuilder(
        environment: <String, String>{
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

    test('throws when the fastlane runner directory does not exist', () {
      // The profile points at a runner path whose parent directory is absent.
      // _buildFastlane must surface a FormatException naming the action.
      final action = CliAction(
        id: 'missing_runner',
        categoryId: 'g',
        title: const <AppLocale, String>{
          AppLocale.tr: 'M',
          AppLocale.en: 'M',
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
        appRootPath: '/tmp/does/not/exist/fastlane_cli_${DateTime.now().microsecondsSinceEpoch}',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'g', actionIds: <String>[action.id]),
        ],
      );

      expect(
        () => const CommandBuilder(environment: <String, String>{})
            .build(profile: profile, action: action),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('runner directory not found'),
              contains('missing_runner'),
            ),
          ),
        ),
      );
    });

    test('flutter command uses the app root as working directory', () {
      final action = CliAction(
        id: 'flutter_clean',
        categoryId: 'general',
        title: const <AppLocale, String>{
          AppLocale.tr: 'C',
          AppLocale.en: 'C',
        },
        description: const <AppLocale, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.flutter,
          arguments: <String>['clean'],
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      final profile = createTestProfile(
        appRootPath: '/tmp/some/app',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      final request = const CommandBuilder().build(profile: profile, action: action);
      expect(request.workingDirectory, '/tmp/some/app');
      // Non-fastlane builds carry no environment overlay.
      expect(request.environment, isEmpty);
    });

    test('custom command uses the app root and forwards exact arguments', () {
      final action = CliAction(
        id: 'custom_ok',
        categoryId: 'general',
        title: const <AppLocale, String>{
          AppLocale.tr: 'C',
          AppLocale.en: 'C',
        },
        description: const <AppLocale, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.custom,
          executable: '/bin/ls',
          arguments: <String>['-la', '/tmp'],
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
      expect(request.executable, '/bin/ls');
      expect(request.arguments, <String>['-la', '/tmp']);
      expect(request.workingDirectory, '/tmp/app');
    });

    test('throws when custom executable is null', () {
      final action = CliAction(
        id: 'custom_null',
        categoryId: 'general',
        title: const <AppLocale, String>{
          AppLocale.tr: 'C',
          AppLocale.en: 'C',
        },
        description: const <AppLocale, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.custom,
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

    test('throws when fastlane lane is null', () {
      final action = CliAction(
        id: 'null_lane',
        categoryId: 'g',
        title: const <AppLocale, String>{
          AppLocale.tr: 'N',
          AppLocale.en: 'N',
        },
        description: const <AppLocale, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.fastlane,
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
