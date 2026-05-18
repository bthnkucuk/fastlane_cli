import 'dart:io';

import 'package:fastlane_cli/src/cli/profile_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProfileResolver', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('profile_resolver_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('uses --profile when provided and file exists', () {
      final flagPath = p.join(tempDir.path, 'flag.yaml');
      File(flagPath).writeAsStringSync('app:');
      final envPath = p.join(tempDir.path, 'env.yaml');
      File(envPath).writeAsStringSync('app:');
      File(p.join(tempDir.path, 'cli_profile.yaml')).writeAsStringSync('app:');

      final resolver = ProfileResolver(
        environment: <String, String>{'FASTLANE_CLI_PROFILE': envPath},
        workingDirectory: tempDir,
      );
      expect(resolver.resolve(explicit: flagPath), flagPath);
    });

    test(r'falls back to $FASTLANE_CLI_PROFILE when --profile absent', () {
      final envPath = p.join(tempDir.path, 'env.yaml');
      File(envPath).writeAsStringSync('app:');
      File(p.join(tempDir.path, 'cli_profile.yaml')).writeAsStringSync('app:');

      final resolver = ProfileResolver(
        environment: <String, String>{'FASTLANE_CLI_PROFILE': envPath},
        workingDirectory: tempDir,
      );
      expect(resolver.resolve(), envPath);
    });

    test('falls back to ./cli_profile.yaml when other sources missing', () {
      final cwdPath = p.join(tempDir.path, 'cli_profile.yaml');
      File(cwdPath).writeAsStringSync('app:');

      final resolver = ProfileResolver(
        environment: const <String, String>{},
        workingDirectory: tempDir,
      );
      expect(resolver.resolve(), cwdPath);
    });

    test('throws ProfileResolutionException listing all three sources', () {
      final resolver = ProfileResolver(
        environment: const <String, String>{},
        workingDirectory: tempDir,
      );
      expect(
        () => resolver.resolve(),
        throwsA(
          isA<ProfileResolutionException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('--profile'),
              contains('FASTLANE_CLI_PROFILE'),
              contains('cli_profile.yaml'),
            ),
          ),
        ),
      );
    });

    test('explicit relative --profile is resolved against cwd', () {
      final flagPath = p.join(tempDir.path, 'rel.yaml');
      File(flagPath).writeAsStringSync('app:');

      final resolver = ProfileResolver(
        environment: const <String, String>{},
        workingDirectory: tempDir,
      );
      expect(resolver.resolve(explicit: 'rel.yaml'), flagPath);
    });
  });
}
