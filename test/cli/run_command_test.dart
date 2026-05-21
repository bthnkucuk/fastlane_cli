import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart';
import 'package:fastlane_cli/src/services/profile_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/profile_factory.dart';

void main() {
  group('RunCommand', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('run_cmd_');
      // Profile file just needs to exist so the resolver succeeds.
      File(p.join(tempDir.path, 'profile.yaml'))
          .writeAsStringSync('app:');
      // Builder requires the fastlane runner directory to exist.
      Directory(p.join(tempDir.path, 'fastlane')).createSync(recursive: true);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    CliProfile buildProfile() {
      final action1 = makeFastlaneAction(
        id: 'android_version_status',
        categoryId: 'android',
        lane: 'version_status',
        platform: 'android',
      );
      final action2 = makeFastlaneAction(
        id: 'ios_release',
        categoryId: 'ios',
        lane: 'release',
        platform: 'ios',
      );
      return createTestProfile(
        appRootPath: tempDir.path,
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>['android_version_status']),
          makeCategory(id: 'ios', actionIds: <String>['ios_release']),
        ],
        actions: <CliAction>[action1, action2],
      );
    }

    Future<({int? exit, _FakeExecutor executor, String stderr})> runRun(
      List<String> args,
      CliProfile profile, {
      int returnExit = 0,
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final executor = _FakeExecutor(exitCode: returnExit);
      final command = RunCommand(
        profileLoader: _StaticLoader(profile),
        profileResolver: ProfileResolver(workingDirectory: tempDir),
        commandBuilder: const CommandBuilder(),
        executionService: executor,
        stdoutSink: out,
        stderrSink: err,
      );
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);
      final code = await runner.run(<String>['run', ...args]);
      return (exit: code, executor: executor, stderr: err.toString());
    }

    test('picks the action by id and forwards its lane to CommandBuilder',
        () async {
      final result = await runRun(
        const <String>['android_version_status'],
        buildProfile(),
      );
      expect(result.exit, 0);
      expect(result.executor.invocations, hasLength(1));
      final request = result.executor.invocations.single.request;
      expect(request.executable, 'fastlane');
      expect(request.arguments, <String>['android', 'version_status']);
    });

    test('propagates the lane exit code', () async {
      final result = await runRun(
        const <String>['android_version_status'],
        buildProfile(),
        returnExit: 42,
      );
      expect(result.exit, 42);
    });

    test('--option key=value merges into the action options', () async {
      final result = await runRun(
        const <String>[
          'android_version_status',
          '--option',
          'flavor=staging',
          '--option',
          'track=internal',
        ],
        buildProfile(),
      );
      expect(result.exit, 0);
      final args = result.executor.invocations.single.request.arguments;
      expect(args, contains('flavor:staging'));
      expect(args, contains('track:internal'));
    });

    test('rejects malformed --option entries', () async {
      final result = await runRun(
        const <String>['android_version_status', '--option', 'bogus'],
        buildProfile(),
      );
      expect(result.exit, 64);
      expect(result.executor.invocations, isEmpty);
      expect(result.stderr, contains('Invalid --option'));
    });

    test('unknown action id exits 64 with helpful stderr', () async {
      final result = await runRun(
        const <String>['no_such_action'],
        buildProfile(),
      );
      expect(result.exit, 64);
      expect(result.executor.invocations, isEmpty);
      expect(result.stderr, contains('Unknown action id'));
    });

    test('missing action id exits 64', () async {
      final result = await runRun(const <String>[], buildProfile());
      expect(result.exit, 64);
      expect(result.stderr, contains('Missing required'));
    });

    test('--dry-run is forwarded to executor', () async {
      final result = await runRun(
        const <String>['android_version_status', '--dry-run'],
        buildProfile(),
      );
      expect(result.exit, 0);
      expect(result.executor.invocations.single.dryRun, isTrue);
    });
  });
}

class _StaticLoader extends ProfileLoader {
  _StaticLoader(this._profile);

  final CliProfile _profile;

  @override
  Future<CliProfile> load(String profilePath) async => _profile;
}

class _FakeExecutor implements CommandExecutionService {
  _FakeExecutor({this.exitCode = 0});

  final int exitCode;
  final List<_Invocation> invocations = <_Invocation>[];

  @override
  Future<CommandExecutionResult> run(
    CommandRequest request, {
    required bool dryRun,
    required void Function(CommandLogEvent event) onLog,
    void Function(RunningProcess process)? onProcess,
  }) async {
    invocations.add(_Invocation(request: request, dryRun: dryRun));
    onLog(const CommandLogEvent(message: 'fake stdout', isError: false));
    return CommandExecutionResult(exitCode: exitCode, wasDryRun: dryRun);
  }
}

class _Invocation {
  _Invocation({required this.request, required this.dryRun});
  final CommandRequest request;
  final bool dryRun;
}

