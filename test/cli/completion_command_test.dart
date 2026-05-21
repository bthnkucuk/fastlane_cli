import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/profile_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/profile_factory.dart';

void main() {
  group('CompletionCommand', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('completion_');
      File(p.join(tempDir.path, 'profile.yaml'))
          .writeAsStringSync('app:');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    CliProfile buildProfile() {
      return createTestProfile(
        appRootPath: tempDir.path,
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>['a1']),
        ],
        actions: <CliAction>[
          makeFastlaneAction(id: 'a1', categoryId: 'android', lane: 'la'),
          makeFastlaneAction(id: 'a2', categoryId: 'android', lane: 'lb'),
        ],
      );
    }

    Future<({int? exit, String stdout})> runCompletion(
      List<String> args, {
      CliProfile? profile,
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final command = CompletionCommand(
        profileLoader: profile == null
            ? const ProfileLoader()
            : _StaticLoader(profile),
        profileResolver: ProfileResolver(workingDirectory: tempDir),
        stdoutSink: out,
        stderrSink: err,
      );
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);
      final code = await runner.run(<String>['completion', ...args]);
      return (exit: code, stdout: out.toString());
    }

    test('bash script mentions every subcommand name', () async {
      final result = await runCompletion(<String>['bash'], profile: buildProfile());
      expect(result.exit, 0);
      for (final sub in CompletionCommand.defaultSubcommands) {
        expect(result.stdout, contains(sub),
            reason: 'bash script missing subcommand "$sub"');
      }
    });

    test('bash script lists action ids when profile is discoverable',
        () async {
      final result =
          await runCompletion(<String>['bash'], profile: buildProfile());
      expect(result.stdout, contains('a1'));
      expect(result.stdout, contains('a2'));
    });

    test('zsh script mentions every subcommand name', () async {
      final result = await runCompletion(<String>['zsh'], profile: buildProfile());
      expect(result.exit, 0);
      for (final sub in CompletionCommand.defaultSubcommands) {
        expect(result.stdout, contains(sub),
            reason: 'zsh script missing subcommand "$sub"');
      }
    });

    test('fish script mentions every subcommand name', () async {
      final result = await runCompletion(<String>['fish'], profile: buildProfile());
      expect(result.exit, 0);
      for (final sub in CompletionCommand.defaultSubcommands) {
        expect(result.stdout, contains(sub),
            reason: 'fish script missing subcommand "$sub"');
      }
    });

    test('missing shell argument exits 64', () async {
      final result = await runCompletion(const <String>[]);
      expect(result.exit, 64);
    });

    test('unknown shell exits 64', () async {
      final result = await runCompletion(<String>['powershell']);
      expect(result.exit, 64);
    });

    test('still emits a usable script even when no profile is discoverable',
        () async {
      // Use an unrelated empty dir so the resolver fails fast.
      final emptyDir =
          await Directory.systemTemp.createTemp('completion_empty_');
      addTearDown(() => emptyDir.delete(recursive: true));

      final out = StringBuffer();
      final command = CompletionCommand(
        profileResolver: ProfileResolver(
          environment: const <String, String>{},
          workingDirectory: emptyDir,
        ),
        stdoutSink: out,
        stderrSink: StringBuffer(),
      );
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);
      final code = await runner.run(<String>['completion', 'bash']);
      expect(code, 0);
      for (final sub in CompletionCommand.defaultSubcommands) {
        expect(out.toString(), contains(sub));
      }
    });
  });
}

class _StaticLoader extends ProfileLoader {
  _StaticLoader(this._profile);

  final CliProfile _profile;

  @override
  Future<CliProfile> load(String profilePath) async => _profile;
}
