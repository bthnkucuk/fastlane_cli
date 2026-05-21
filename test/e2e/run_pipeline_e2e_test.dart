import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart';
import 'package:fastlane_cli/src/services/profile_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/profile_fixtures.dart';

/// End-to-end coverage of the full headless pipeline:
///
///   profile.yaml on disk
///     → ProfileResolver  (discovery precedence)
///     → ProfileLoader    (base-merge + default_options fold)
///     → action resolution
///     → CommandBuilder   (CliProfile + CliAction → CommandRequest)
///     → ProcessCommandExecutionService (dry-run: resolve, don't exec)
///
/// Nothing here spawns a real `fastlane` process or touches the network.
/// Every fixture lives in a fresh tmp directory created per test.
void main() {
  group('e2e: profile discovery → CommandRequest pipeline', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('e2e_run_pipeline_');
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    // ---- fixture-on-disk helpers -----------------------------------------

    /// Materialises an app directory under [tempRoot]:
    ///   <app>/pubspec.yaml
    ///   <app>/fastlane/Fastfile          (so RunnerResolver accepts it)
    ///   <app>/fastlane/profile.base.yaml (optional)
    ///   <app>/<profileRelPath>           (the per-app profile)
    ///
    /// Returns the absolute path of the written profile file.
    String seedApp({
      required String profileYaml,
      String profileRelPath = 'profile.yaml',
      String? baseYaml,
      String appDirName = 'app',
    }) {
      final app = Directory(p.join(tempRoot.path, appDirName))
        ..createSync(recursive: true);
      File(p.join(app.path, 'pubspec.yaml'))
          .writeAsStringSync('name: my_app\n');
      final fastlaneDir = Directory(p.join(app.path, 'fastlane'))
        ..createSync(recursive: true);
      File(p.join(fastlaneDir.path, 'Fastfile'))
          .writeAsStringSync('# stub Fastfile\n');
      if (baseYaml != null) {
        File(p.join(fastlaneDir.path, 'profile.base.yaml'))
            .writeAsStringSync(baseYaml);
      }
      final profileFile = File(p.join(app.path, profileRelPath))
        ..createSync(recursive: true)
        ..writeAsStringSync(profileYaml);
      return profileFile.absolute.path;
    }

    /// A [RunnerResolver] pinned to a known `fastlane/` directory so loader
    /// runs are hermetic — they never depend on the host's real runner being
    /// discoverable via `Platform.resolvedExecutable`.
    ProfileLoader loaderFor(String fastlaneDir) =>
        ProfileLoader(runnerResolver: _PinnedRunnerResolver(fastlaneDir));

    String fastlaneDirOf(String profilePath) =>
        p.join(p.dirname(profilePath), 'fastlane');

    // ======================================================================
    // 1. Profile discovery — every ProfileResolver precedence step.
    // ======================================================================

    group('ProfileResolver discovery precedence', () {
      test('explicit --profile pointing directly at a file wins', () {
        final path = seedApp(profileYaml: fullProfileYaml);
        final sink = StringBuffer();
        final resolver = ProfileResolver(
          environment: const <String, String>{},
          workingDirectory: tempRoot,
          discoverySink: sink,
        );
        expect(resolver.resolve(explicit: path), path);
        // Direct file path → resolver emits no "discovered:" line.
        expect(sink.toString(), isEmpty);
      });

      test('explicit --profile pointing at a directory finds profile.yaml',
          () {
        final path = seedApp(profileYaml: fullProfileYaml);
        final appDir = p.dirname(path);
        final sink = StringBuffer();
        final resolver = ProfileResolver(
          environment: const <String, String>{},
          workingDirectory: tempRoot,
          discoverySink: sink,
        );
        expect(resolver.resolve(explicit: appDir), path);
        expect(sink.toString(), contains('discovered: $path'));
      });

      test(r'$FASTLANE_CLI_PROFILE env var is honoured when --profile absent',
          () {
        final path = seedApp(profileYaml: fullProfileYaml);
        final resolver = ProfileResolver(
          environment: <String, String>{'FASTLANE_CLI_PROFILE': path},
          workingDirectory: tempRoot,
          discoverySink: StringBuffer(),
        );
        expect(resolver.resolve(), path);
      });

      test('walk-up discovery finds fastlane/profile.yaml from a deep cwd', () {
        // profile lives at <app>/fastlane/profile.yaml; cwd is <app>/lib/src.
        final path = seedApp(
          profileYaml: fullProfileYaml,
          profileRelPath: p.join('fastlane', 'profile.yaml'),
        );
        final deepCwd = Directory(
          p.join(p.dirname(p.dirname(path)), 'lib', 'src'),
        )..createSync(recursive: true);
        final sink = StringBuffer();
        final resolver = ProfileResolver(
          environment: const <String, String>{},
          workingDirectory: deepCwd,
          discoverySink: sink,
        );
        expect(resolver.resolve(), path);
        expect(sink.toString(), contains('discovered: $path'));
      });

      test('./profile.yaml in cwd is the final fallback', () {
        final path = seedApp(profileYaml: fullProfileYaml);
        final cwd = Directory(p.dirname(path));
        final resolver = ProfileResolver(
          environment: const <String, String>{},
          workingDirectory: cwd,
          discoverySink: StringBuffer(),
        );
        expect(resolver.resolve(), path);
      });

      test('precedence: explicit --profile beats env var and walk-up', () {
        final flagPath = seedApp(
          profileYaml: fullProfileYaml,
          appDirName: 'flag_app',
        );
        final envPath = seedApp(
          profileYaml: fullProfileYaml,
          appDirName: 'env_app',
        );
        final resolver = ProfileResolver(
          environment: <String, String>{'FASTLANE_CLI_PROFILE': envPath},
          workingDirectory: tempRoot,
          discoverySink: StringBuffer(),
        );
        expect(resolver.resolve(explicit: flagPath), flagPath);
      });

      test(
          'deprecated cli_profile.yaml is still resolved and emits a '
          'one-time deprecation warning', () {
        // Seed the app but rename the profile to the legacy file name.
        final app = Directory(p.join(tempRoot.path, 'legacy_app'))
          ..createSync(recursive: true);
        final legacy = File(p.join(app.path, 'cli_profile.yaml'))
          ..writeAsStringSync(fullProfileYaml);
        final sink = StringBuffer();
        final resolver = ProfileResolver(
          environment: const <String, String>{},
          workingDirectory: app,
          discoverySink: sink,
        );
        expect(resolver.resolve(), legacy.absolute.path);
        expect(
          sink.toString(),
          contains('cli_profile.yaml is deprecated'),
        );
      });
    });

    // ======================================================================
    // 2. Full pipeline: profile.yaml → CommandRequest.
    // ======================================================================

    group('full pipeline → CommandRequest', () {
      test(
          'a plain fastlane action inherits every default_options key into '
          'the final argv', () async {
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        final action = profile.actionsById['android_internal']!;
        final request =
            const CommandBuilder().build(profile: profile, action: action);

        // Executable contract: system gem, never `bundle exec`.
        expect(request.executable, 'fastlane');
        // Platform + lane positional args lead the argv.
        expect(request.arguments[0], 'android');
        expect(request.arguments[1], 'internal_testing');
        // default_options folded into the argv as key:value pairs.
        expect(request.arguments, contains('flavor:dev'));
        expect(request.arguments, contains('target:lib/main_dev.dart'));
        expect(request.arguments, contains('obfuscate:false'));
      });

      test('CommandRequest carries the runner workingDirectory and forwarded '
          'FASTLANE_* environment', () async {
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final appDir = p.dirname(profilePath);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        final request = const CommandBuilder().build(
          profile: profile,
          action: profile.actionsById['ios_testflight']!,
        );

        // workingDirectory is dirname(fastlaneRunnerPath) — the app root here.
        expect(request.workingDirectory, p.normalize(appDir));
        // The three FASTLANE_* keys the runner contract requires.
        expect(request.environment['FASTLANE_ROOT'],
            p.join(appDir, 'fastlane'));
        expect(request.environment['FASTLANE_APP_ROOT'],
            p.normalize(appDir));
        expect(request.environment['FASTLANE_CLI_FASTLANE_PATH'],
            p.join(appDir, 'fastlane'));
      });

      test('a flutter action builds an fvm flutter argv, not a fastlane one',
          () async {
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        final request = const CommandBuilder().build(
          profile: profile,
          action: profile.actionsById['run_tests']!,
        );

        expect(request.executable, 'fvm');
        expect(request.arguments, <String>['flutter', 'test']);
        // default_options must NOT leak into non-fastlane commands.
        expect(request.arguments, isNot(contains('flavor:dev')));
      });

      test('app profile.yaml merges over profile.base.yaml during e2e load',
          () async {
        final profilePath = seedApp(
          profileYaml: overlayProfileYaml,
          baseYaml: baseProfileYaml,
        );
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        // Category came from the base; the action id was overridden by the
        // app overlay (merge-by-id), and the overlay title must win.
        final action = profile.actionsById['android_internal']!;
        expect(action.title[AppLocale.en], 'Android internal (overlay)');

        final request =
            const CommandBuilder().build(profile: profile, action: action);
        // base default_options.region survives, app default_options.flavor
        // wins over the base value, and the action's own track is kept.
        expect(request.arguments, contains('region:us'));
        expect(request.arguments, contains('flavor:staging'));
        expect(request.arguments, contains('track:beta'));
      });
    });

    // ======================================================================
    // 3. Option precedence: default_options < command.options < --option.
    // ======================================================================

    group('option precedence across all three layers', () {
      test('per-action command.options overrides a default_options key',
          () async {
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        // android_production declares its own flavor/target/upload_symbols.
        final request = const CommandBuilder().build(
          profile: profile,
          action: profile.actionsById['android_production']!,
        );
        // command.options win over default_options for `flavor` + `target`.
        expect(request.arguments, contains('flavor:prod'));
        expect(request.arguments, contains('target:lib/main_prod.dart'));
        // default_options.obfuscate (no per-action override) still present.
        expect(request.arguments, contains('obfuscate:false'));
        // per-action-only key forwarded too.
        expect(request.arguments, contains('upload_symbols:true'));
        // The losing default_options.flavor value must NOT appear.
        expect(request.arguments, isNot(contains('flavor:dev')));
      });

      test(
          '--option CLI flag is the top-precedence winner over both '
          'default_options and command.options', () async {
        // Drive the real RunCommand so the --option merge path executes.
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final executor = _CapturingExecutor();
        final result = await _runRun(
          args: <String>[
            'android_production',
            '--profile',
            profilePath,
            // flavor is set in BOTH default_options and command.options;
            // the CLI flag must beat both.
            '--option',
            'flavor=cli_wins',
            // obfuscate is set only in default_options; the flag beats it.
            '--option',
            'obfuscate=true',
          ],
          fastlaneDir: fastlaneDirOf(profilePath),
          executor: executor,
        );

        expect(result.exitCode, 0);
        final argv = executor.lastRequest!.arguments;
        expect(argv, contains('flavor:cli_wins'));
        expect(argv, contains('obfuscate:true'));
        // Neither lower-precedence flavor value survives.
        expect(argv, isNot(contains('flavor:prod')));
        expect(argv, isNot(contains('flavor:dev')));
        // A key untouched by the flag keeps its action-level value.
        expect(argv, contains('target:lib/main_prod.dart'));
      });
    });

    // ======================================================================
    // 3b. App-block identity: app.package_name / app.bundle_id reach argv,
    //     and lose to default_options / command.options / --option flag.
    // ======================================================================

    group('app: block identity (package_name / bundle_id)', () {
      test('app.package_name and app.bundle_id reach the fastlane argv',
          () async {
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        // Model carries the parsed identity.
        expect(profile.packageName, 'com.example.myapp');
        expect(profile.bundleId, 'com.example.myapp.ios');

        // android_internal declares no package_name of its own → the
        // app: block identity is folded in as the `package_name` option.
        final request = const CommandBuilder().build(
          profile: profile,
          action: profile.actionsById['android_internal']!,
        );
        expect(request.arguments, contains('package_name:com.example.myapp'));
        expect(
          request.arguments,
          contains('app_identifier:com.example.myapp.ios'),
        );
      });

      test('default_options outranks the app: block identity', () async {
        final profilePath =
            seedApp(profileYaml: identityOverriddenByDefaultOptionsYaml);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        final request = const CommandBuilder().build(
          profile: profile,
          action: profile.actionsById['android_ship']!,
        );
        // default_options value wins on collision.
        expect(
          request.arguments,
          contains('package_name:com.example.defaultopts'),
        );
        expect(
          request.arguments,
          contains('app_identifier:com.example.defaultopts.ios'),
        );
        // The losing app: block identity must NOT appear.
        expect(
          request.arguments,
          isNot(contains('package_name:com.example.appblock')),
        );
      });

      test('per-action command.options outranks the app: block identity',
          () async {
        final profilePath =
            seedApp(profileYaml: identityOverriddenByActionOptionsYaml);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        final request = const CommandBuilder().build(
          profile: profile,
          action: profile.actionsById['android_ship']!,
        );
        // The per-action option wins; the app: block identity loses.
        expect(
          request.arguments,
          contains('package_name:com.example.actionopts'),
        );
        expect(
          request.arguments,
          isNot(contains('package_name:com.example.appblock')),
        );
      });

      test('--option flag outranks the app: block identity', () async {
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final executor = _CapturingExecutor();
        final result = await _runRun(
          args: <String>[
            'android_internal',
            '--profile',
            profilePath,
            '--option',
            'package_name=com.example.cliflag',
          ],
          fastlaneDir: fastlaneDirOf(profilePath),
          executor: executor,
        );

        expect(result.exitCode, 0);
        final argv = executor.lastRequest!.arguments;
        expect(argv, contains('package_name:com.example.cliflag'));
        // The app: block identity must NOT survive the flag.
        expect(argv, isNot(contains('package_name:com.example.myapp')));
      });

      test('a profile with neither identity key still loads and runs',
          () async {
        // overlayProfileYaml carries no package_name / bundle_id.
        final profilePath = seedApp(
          profileYaml: overlayProfileYaml,
          baseYaml: baseProfileYaml,
        );
        final loader = loaderFor(fastlaneDirOf(profilePath));
        final profile = await loader.load(profilePath);

        expect(profile.packageName, isNull);
        expect(profile.bundleId, isNull);

        final request = const CommandBuilder().build(
          profile: profile,
          action: profile.actionsById['android_internal']!,
        );
        // No identity options leak in when the keys are absent.
        expect(
          request.arguments.any((a) => a.startsWith('package_name:')),
          isFalse,
        );
        expect(
          request.arguments.any((a) => a.startsWith('app_identifier:')),
          isFalse,
        );
      });
    });

    // ======================================================================
    // 4. --dry-run e2e through the real RunCommand + execution service.
    // ======================================================================

    group('--dry-run resolves without executing', () {
      test(
          'dry-run drives the real ProcessCommandExecutionService and emits '
          'the resolved fastlane command without spawning a process',
          () async {
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final out = StringBuffer();
        final err = StringBuffer();

        // Real RunCommand + real ProcessCommandExecutionService. The dry-run
        // branch returns before any Process.start, so this is hermetic even
        // though no `fastlane` binary exists.
        final command = RunCommand(
          profileLoader: loaderFor(fastlaneDirOf(profilePath)),
          executionService:
              ProcessCommandExecutionService(useUnixPty: false),
          stdoutSink: out,
          stderrSink: err,
        );
        final runner = CommandRunner<int>('test', 'test')
          ..addCommand(command);
        final code = await runner.run(<String>[
          'run',
          'android_internal',
          '--profile',
          profilePath,
          '--dry-run',
        ]);

        expect(code, 0);
        final logged = out.toString();
        // Structural assertions — not a verbatim snapshot.
        expect(logged, contains('[dry-run]'));
        expect(logged, contains('fastlane android internal_testing'));
        expect(logged, contains('flavor:dev'));
        // No spawn / exec lines appeared.
        expect(logged, isNot(contains('[exec]')));
        expect(err.toString(), isEmpty);
      });

      test('dry-run redacts secret-looking env values it would forward',
          () async {
        // Seed a fastlane/.env carrying a secret-looking key; the dry-run
        // logger forwards env keys but must redact the value.
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        File(p.join(fastlaneDirOf(profilePath), '.env')).writeAsStringSync(
          'GOOGLE_PLAY_JSON_KEY_DATA=super-secret-value\n'
          'PLAIN_KEY=visible-value\n',
        );
        final out = StringBuffer();
        final command = RunCommand(
          profileLoader: loaderFor(fastlaneDirOf(profilePath)),
          executionService:
              ProcessCommandExecutionService(useUnixPty: false),
          stdoutSink: out,
          stderrSink: StringBuffer(),
        );
        final runner = CommandRunner<int>('test', 'test')
          ..addCommand(command);
        final code = await runner.run(<String>[
          'run',
          'android_internal',
          '--profile',
          profilePath,
          '--dry-run',
        ]);

        expect(code, 0);
        final logged = out.toString();
        expect(logged, contains('PLAIN_KEY=visible-value'));
        // The secret value must never reach the log.
        expect(logged, isNot(contains('super-secret-value')));
        expect(logged, contains('GOOGLE_PLAY_JSON_KEY_DATA=***'));
      });
    });

    // ======================================================================
    // 5. Failure paths.
    // ======================================================================

    group('failure paths', () {
      test('missing profile → clear "Could not locate profile.yaml" error',
          () async {
        // No profile.yaml anywhere; resolver must surface the remediation.
        final emptyCwd = Directory(p.join(tempRoot.path, 'empty'))
          ..createSync(recursive: true);
        final executor = _CapturingExecutor();
        final err = StringBuffer();
        final command = RunCommand(
          executionService: executor,
          profileResolver: ProfileResolver(
            environment: const <String, String>{},
            workingDirectory: emptyCwd,
            discoverySink: StringBuffer(),
          ),
          stdoutSink: StringBuffer(),
          stderrSink: err,
        );
        final runner = CommandRunner<int>('test', 'test')
          ..addCommand(command);
        final code = await runner.run(<String>['run', 'android_internal']);

        // RunCommand maps ProfileResolutionException → exit 66.
        expect(code, 66);
        expect(err.toString(), contains('Could not locate profile.yaml'));
        expect(executor.invocations, isEmpty);
      });

      test('malformed YAML profile surfaces a FormatException', () async {
        final profilePath = seedApp(profileYaml: malformedProfileYaml);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        expect(
          () => loader.load(profilePath),
          throwsA(isA<Exception>()),
        );
      });

      test('profile with an action pointing at an unknown category is '
          'rejected by loader validation', () async {
        final profilePath = seedApp(profileYaml: inconsistentProfileYaml);
        final loader = loaderFor(fastlaneDirOf(profilePath));
        expect(
          () => loader.load(profilePath),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('unknown category'),
            ),
          ),
        );
      });

      test('unknown action id → exit 64 with a helpful hint', () async {
        final profilePath = seedApp(profileYaml: fullProfileYaml);
        final executor = _CapturingExecutor();
        final err = StringBuffer();
        final result = await _runRun(
          args: <String>[
            'no_such_action',
            '--profile',
            profilePath,
          ],
          fastlaneDir: fastlaneDirOf(profilePath),
          executor: executor,
          stderrSink: err,
        );
        expect(result.exitCode, 64);
        expect(err.toString(), contains('Unknown action id'));
        expect(executor.invocations, isEmpty);
      });
    });
  });
}

/// Runs the real [RunCommand] (real [ProfileLoader] + real [CommandBuilder])
/// against a fixture-on-disk profile, with a capturing executor so the
/// resolved [CommandRequest] can be asserted without spawning a process.
Future<({int exitCode})> _runRun({
  required List<String> args,
  required String fastlaneDir,
  required _CapturingExecutor executor,
  StringSink? stdoutSink,
  StringSink? stderrSink,
}) async {
  final command = RunCommand(
    profileLoader: ProfileLoader(
      runnerResolver: _PinnedRunnerResolver(fastlaneDir),
    ),
    executionService: executor,
    stdoutSink: stdoutSink ?? StringBuffer(),
    stderrSink: stderrSink ?? StringBuffer(),
  );
  final runner = CommandRunner<int>('test', 'test')..addCommand(command);
  final code = await runner.run(<String>['run', ...args]);
  return (exitCode: code ?? 0);
}

/// A [RunnerResolver] pinned to a fixed fastlane directory so e2e profile
/// loads never depend on host-discoverable runner assets.
class _PinnedRunnerResolver extends RunnerResolver {
  _PinnedRunnerResolver(this._fastlaneDir);

  final String _fastlaneDir;

  @override
  Future<String> resolve({String? profileOverride}) async => _fastlaneDir;
}

/// Captures every [CommandRequest] handed to the execution service so the
/// final argv/env/cwd can be inspected. Never spawns anything.
class _CapturingExecutor implements CommandExecutionService {
  final List<CommandRequest> invocations = <CommandRequest>[];

  CommandRequest? get lastRequest =>
      invocations.isEmpty ? null : invocations.last;

  @override
  Future<CommandExecutionResult> run(
    CommandRequest request, {
    required bool dryRun,
    required void Function(CommandLogEvent event) onLog,
    void Function(RunningProcess process)? onProcess,
  }) async {
    invocations.add(request);
    return CommandExecutionResult(exitCode: 0, wasDryRun: dryRun);
  }
}
