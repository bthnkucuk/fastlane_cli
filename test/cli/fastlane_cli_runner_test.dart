import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:test/test.dart';

void main() {
  group('FastlaneCliRunner --version', () {
    test('--version prints "fastlane_cli <version>" and exits 0', () async {
      final out = StringBuffer();
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(
        launcher: launcher,
        stdoutSink: out,
      );

      final code = await runner.run(<String>['--version']);

      expect(code, 0);
      expect(out.toString(), 'fastlane_cli $fastlaneCliVersion\n');
      // Did NOT delegate to the TUI launcher.
      expect(launcher.runCallCount, 0);
    });

    test('-v short alias matches --version', () async {
      final out = StringBuffer();
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(
        launcher: launcher,
        stdoutSink: out,
      );

      final code = await runner.run(<String>['-v']);

      expect(code, 0);
      expect(out.toString(), 'fastlane_cli $fastlaneCliVersion\n');
      expect(launcher.runCallCount, 0);
    });

    test(
      '--version short-circuits even when a subcommand follows; '
      'subcommand is NOT invoked and no profile lookup happens',
      () async {
        final out = StringBuffer();
        final launcher = _RecordingLauncher();
        final runner = FastlaneCliRunner(
          launcher: launcher,
          stdoutSink: out,
        );

        // `run get_version_data` would normally require a profile and
        // would otherwise error out before reaching the lane. The version
        // flag must win.
        final code = await runner.run(
          <String>['--version', 'run', 'get_version_data'],
        );

        expect(code, 0);
        expect(out.toString(), 'fastlane_cli $fastlaneCliVersion\n');
        expect(launcher.runCallCount, 0);
      },
    );

    test('version constant matches semver shape X.Y.Z', () {
      // Guards against accidental edits like `0.3.0+1` or `v0.3.0`. The
      // homebrew formula's `version` line + pubspec `version:` rely on
      // this format.
      expect(
        fastlaneCliVersion,
        matches(RegExp(r'^\d+\.\d+\.\d+$')),
      );
    });
  });

  group('FastlaneCliRunner TUI delegation', () {
    test('no arguments delegates to the TUI launcher', () async {
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(launcher: launcher);

      final code = await runner.run(const <String>[]);

      expect(code, 0);
      expect(launcher.runCallCount, 1);
    });

    test('only top-level flags (no subcommand) delegates to the TUI', () async {
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(launcher: launcher);

      // `--profile <p> --dry-run` is a TUI invocation: no subcommand follows.
      final code = await runner.run(
        const <String>['--profile', '/tmp/profile.yaml', '--dry-run'],
      );

      expect(code, 0);
      expect(launcher.runCallCount, 1);
      expect(
        launcher.lastArgs,
        const <String>['--profile', '/tmp/profile.yaml', '--dry-run'],
      );
    });

    test('a known subcommand does NOT delegate to the TUI', () async {
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(launcher: launcher);

      // `list` with no resolvable profile fails inside the command (exit 66),
      // but the key assertion is that the TUI launcher was never invoked.
      final code = await runner.run(
        const <String>['list', '--profile', '/no/such/profile.yaml'],
      );

      expect(launcher.runCallCount, 0);
      expect(code, isNot(0));
    });

    test('everything after `--` is treated as TUI positionals', () async {
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(launcher: launcher);

      final code = await runner.run(const <String>['--', 'list']);

      expect(code, 0);
      expect(launcher.runCallCount, 1);
    });

    test('an unknown positional is treated as a TUI argument, not an error',
        () async {
      // `_shouldDelegateToTui` only refuses to delegate when the first
      // positional is a *known* subcommand. An unknown positional is a
      // legacy TUI-style argument and is handed to the launcher.
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(launcher: launcher);

      final code = await runner.run(const <String>['not-a-real-command']);

      expect(code, 0);
      expect(launcher.runCallCount, 1);
    });

    test('an unknown flag before a subcommand surfaces a UsageException → 64',
        () async {
      // A leading unknown flag stops TUI delegation (`_shouldDelegateToTui`
      // returns false for unknown flags) and CommandRunner then rejects it.
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(launcher: launcher);

      final code = await runner.run(const <String>['--definitely-not-a-flag']);

      expect(code, 64);
      expect(launcher.runCallCount, 0);
    });

    test('a subcommand-level usage error exits 64', () async {
      // `run` requires an <action-id>; passing an unknown flag to it makes
      // CommandRunner throw a UsageException the runner maps to exit 64.
      final launcher = _RecordingLauncher();
      final runner = FastlaneCliRunner(launcher: launcher);

      final code = await runner.run(
        const <String>['run', '--no-such-run-flag'],
      );

      expect(code, 64);
      expect(launcher.runCallCount, 0);
    });
  });
}

/// Test double: subclasses [FastlaneCliLauncher] so we can verify the runner
/// did NOT delegate to the TUI launch path when `--version` short-circuits.
/// We don't use mocktail here — the project's CLI tests prefer subclass-fakes.
class _RecordingLauncher extends FastlaneCliLauncher {
  _RecordingLauncher();

  int runCallCount = 0;
  List<String>? lastArgs;

  @override
  Future<int> run(List<String> arguments) async {
    runCallCount++;
    lastArgs = arguments;
    return 0;
  }
}
