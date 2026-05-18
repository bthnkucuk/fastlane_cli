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
}

/// Test double: subclasses [FastlaneCliLauncher] so we can verify the runner
/// did NOT delegate to the TUI launch path when `--version` short-circuits.
/// We don't use mocktail here — the project's CLI tests prefer subclass-fakes.
class _RecordingLauncher extends FastlaneCliLauncher {
  _RecordingLauncher();

  int runCallCount = 0;

  @override
  Future<int> run(List<String> arguments) async {
    runCallCount++;
    return 0;
  }
}
