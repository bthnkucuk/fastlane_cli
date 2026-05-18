import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/profile_loader.dart';
import 'package:test/test.dart';

void main() {
  group('FastlaneCliLauncher', () {
    test('returns 0 for --help', () async {
      final launcher = FastlaneCliLauncher();
      expect(await launcher.run(<String>['--help']), 0);
    });

    test('returns 64 when profile option is missing', () async {
      final launcher = FastlaneCliLauncher();
      expect(await launcher.run(<String>[]), 64);
    });

    test('returns 64 when profile path is empty', () async {
      final launcher = FastlaneCliLauncher();
      expect(await launcher.run(<String>['--profile', '']), 64);
    });

    test('returns 64 when profile load throws FormatException', () async {
      final launcher = FastlaneCliLauncher(
        profileLoader: const _ThrowingProfileLoader(),
      );
      expect(await launcher.run(<String>['--profile', '/any/cli_profile.yaml']), 64);
    });
  });
}

final class _ThrowingProfileLoader extends ProfileLoader {
  const _ThrowingProfileLoader();

  @override
  Future<CliProfile> load(String profilePath) async {
    throw FormatException('Profile load failed');
  }
}
