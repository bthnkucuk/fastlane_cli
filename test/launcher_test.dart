import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/profile_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FastlaneCliLauncher', () {
    test('returns 0 for --help', () async {
      final launcher = FastlaneCliLauncher();
      expect(await launcher.run(<String>['--help']), 0);
    });

    test('returns 64 when profile option is missing and no resolver', () async {
      final launcher = FastlaneCliLauncher();
      expect(await launcher.run(<String>[]), 64);
    });

    test('returns 64 when profile path is empty and no resolver', () async {
      final launcher = FastlaneCliLauncher();
      expect(await launcher.run(<String>['--profile', '']), 64);
    });

    test('returns 64 when profile load throws FormatException', () async {
      final launcher = FastlaneCliLauncher(
        profileLoader: const _ThrowingProfileLoader(),
      );
      expect(
        await launcher.run(<String>['--profile', '/any/cli_profile.yaml']),
        64,
      );
    });

    group('with ProfileResolver wired', () {
      late Directory tempDir;
      late StringBuffer discoverySink;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('launcher_resolver_');
        discoverySink = StringBuffer();
      });

      tearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      test(
        'no-arg + cwd containing fastlane/cli_profile.yaml resolves via walk-up',
        () async {
          // Layout:
          //   <tempDir>/pubspec.yaml
          //   <tempDir>/fastlane/cli_profile.yaml
          File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('name: x');
          final fastlaneDir = Directory(p.join(tempDir.path, 'fastlane'))
            ..createSync();
          final profilePath = p.join(fastlaneDir.path, 'cli_profile.yaml');
          File(profilePath).writeAsStringSync('app:');

          final capture = _CaptureProfileLoader();
          final resolver = ProfileResolver(
            environment: const <String, String>{},
            workingDirectory: tempDir,
            discoverySink: discoverySink,
          );
          final launcher = FastlaneCliLauncher(
            profileLoader: capture,
            resolver: resolver,
          );

          // Launcher returns 64 because our capturing loader throws after we
          // record the resolved path. The thing under test is that resolution
          // happened (i.e. no "Missing --profile" exit-64 short-circuit).
          await launcher.run(const <String>[]);
          expect(capture.resolvedPath, p.normalize(profilePath));
          expect(discoverySink.toString(), contains('discovered:'));
          expect(discoverySink.toString(), contains(p.normalize(profilePath)));
        },
      );

      test('no-arg + cwd with no profile exits 66 with four-source error',
          () async {
        // Empty tempDir → walk-up has nothing to find.
        final stderrBuf = StringBuffer();
        final resolver = ProfileResolver(
          environment: const <String, String>{},
          workingDirectory: tempDir,
          discoverySink: stderrBuf,
          walkUpMaxLevels: 0,
        );
        final launcher = FastlaneCliLauncher(
          profileLoader: const _ThrowingProfileLoader(),
          resolver: resolver,
        );

        // We can't easily redirect stderr, so just verify the exit code.
        final exit = await launcher.run(const <String>[]);
        expect(exit, 66);
      });

      test(
        'explicit --profile <yaml> bypasses the resolver discovery path',
        () async {
          final profilePath = p.join(tempDir.path, 'explicit.yaml');
          File(profilePath).writeAsStringSync('app:');

          final capture = _CaptureProfileLoader();
          final resolver = ProfileResolver(
            environment: const <String, String>{},
            workingDirectory: tempDir,
            discoverySink: discoverySink,
          );
          final launcher = FastlaneCliLauncher(
            profileLoader: capture,
            resolver: resolver,
          );

          await launcher.run(<String>['--profile', profilePath]);
          expect(capture.resolvedPath, profilePath);
          // File-form explicit path → no discovery announcement.
          expect(discoverySink.toString(), isEmpty);
        },
      );
    });
  });
}

final class _ThrowingProfileLoader extends ProfileLoader {
  const _ThrowingProfileLoader();

  @override
  Future<CliProfile> load(String profilePath) async {
    throw const FormatException('Profile load failed');
  }
}

/// Records the resolved path the launcher passed in, then throws so we don't
/// have to spin up the TUI inside a unit test.
final class _CaptureProfileLoader extends ProfileLoader {
  _CaptureProfileLoader();

  String? resolvedPath;

  @override
  Future<CliProfile> load(String profilePath) async {
    resolvedPath = profilePath;
    throw const FormatException('captured');
  }
}
