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

    test('the shell argument is matched case-insensitively (BASH → bash)',
        () async {
      final result =
          await runCompletion(<String>['BASH'], profile: buildProfile());
      expect(result.exit, 0);
      // The bash renderer signature appears regardless of input casing.
      expect(result.stdout, contains('complete -F _fastlane_cli'));
    });

    test('Zsh and Fish are also accepted case-insensitively', () async {
      final zsh = await runCompletion(<String>['ZSH'], profile: buildProfile());
      expect(zsh.exit, 0);
      expect(zsh.stdout, contains('#compdef fastlane_cli'));

      final fish =
          await runCompletion(<String>['Fish'], profile: buildProfile());
      expect(fish.exit, 0);
      expect(fish.stdout, contains('__fish_use_subcommand'));
    });

    test('a malformed profile does not break completion script emission',
        () async {
      // A loader that throws (corrupt profile.yaml) must be swallowed — the
      // completion script still emits, just without action ids.
      final out = StringBuffer();
      final command = CompletionCommand(
        profileLoader: _ThrowingLoader(),
        profileResolver: ProfileResolver(workingDirectory: tempDir),
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

    test('explicit subcommandNames override the default list', () async {
      final out = StringBuffer();
      final command = CompletionCommand(
        subcommandNames: const <String>['alpha', 'beta'],
        profileResolver: ProfileResolver(workingDirectory: tempDir),
        profileLoader: _StaticLoader(buildProfile()),
        stdoutSink: out,
        stderrSink: StringBuffer(),
      );
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);
      final code = await runner.run(<String>['completion', 'fish']);

      expect(code, 0);
      expect(out.toString(), contains('alpha'));
      expect(out.toString(), contains('beta'));
      // Default names are NOT present when an explicit list is supplied.
      expect(out.toString(), isNot(contains('doctor')));
    });
  });
}

class _StaticLoader extends ProfileLoader {
  _StaticLoader(this._profile);

  final CliProfile _profile;

  @override
  Future<CliProfile> load(String profilePath) async => _profile;
}

class _ThrowingLoader extends ProfileLoader {
  _ThrowingLoader();

  @override
  Future<CliProfile> load(String profilePath) async =>
      throw const FormatException('corrupt profile.yaml');
}
