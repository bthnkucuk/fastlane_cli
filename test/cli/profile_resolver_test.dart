import 'dart:io';

import 'package:fastlane_cli/src/cli/profile_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProfileResolver', () {
    late Directory tempDir;
    late StringBuffer discoverySink;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('profile_resolver_');
      discoverySink = StringBuffer();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    ProfileResolver buildResolver({
      Map<String, String>? env,
      Directory? cwd,
    }) {
      return ProfileResolver(
        environment: env ?? const <String, String>{},
        workingDirectory: cwd ?? tempDir,
        discoverySink: discoverySink,
      );
    }

    test('uses --profile when provided and file exists', () {
      final flagPath = p.join(tempDir.path, 'flag.yaml');
      File(flagPath).writeAsStringSync('app:');
      final envPath = p.join(tempDir.path, 'env.yaml');
      File(envPath).writeAsStringSync('app:');
      File(p.join(tempDir.path, 'cli_profile.yaml')).writeAsStringSync('app:');

      final resolver = buildResolver(
        env: <String, String>{'FASTLANE_CLI_PROFILE': envPath},
      );
      expect(resolver.resolve(explicit: flagPath), flagPath);
      // Direct file path → no "discovered:" line.
      expect(discoverySink.toString(), isEmpty);
    });

    test(r'falls back to $FASTLANE_CLI_PROFILE when --profile absent', () {
      final envPath = p.join(tempDir.path, 'env.yaml');
      File(envPath).writeAsStringSync('app:');
      File(p.join(tempDir.path, 'cli_profile.yaml')).writeAsStringSync('app:');

      final resolver = buildResolver(
        env: <String, String>{'FASTLANE_CLI_PROFILE': envPath},
      );
      expect(resolver.resolve(), envPath);
    });

    test('falls back to ./cli_profile.yaml when other sources missing', () {
      final cwdPath = p.join(tempDir.path, 'cli_profile.yaml');
      File(cwdPath).writeAsStringSync('app:');

      final resolver = buildResolver();
      expect(resolver.resolve(), cwdPath);
    });

    test(
        'throws ProfileResolutionException listing all four sources',
        () {
      final resolver = buildResolver();
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
              contains('walk-up'),
            ),
          ),
        ),
      );
    });

    test('explicit relative --profile is resolved against cwd', () {
      final flagPath = p.join(tempDir.path, 'rel.yaml');
      File(flagPath).writeAsStringSync('app:');

      final resolver = buildResolver();
      expect(resolver.resolve(explicit: 'rel.yaml'), flagPath);
    });

    test('--profile pointing at a dir finds cli_profile.yaml inside', () {
      final dir = Directory(p.join(tempDir.path, 'project'))
        ..createSync(recursive: true);
      final inside = p.join(dir.path, 'cli_profile.yaml');
      File(inside).writeAsStringSync('app:');

      final resolver = buildResolver();
      expect(resolver.resolve(explicit: dir.path), inside);
      expect(discoverySink.toString(), contains('discovered: $inside'));
    });

    test('--profile pointing at a dir finds fastlane/cli_profile.yaml', () {
      final dir = Directory(p.join(tempDir.path, 'project'))
        ..createSync(recursive: true);
      final inside = p.join(dir.path, 'fastlane', 'cli_profile.yaml');
      File(inside)
        ..createSync(recursive: true)
        ..writeAsStringSync('app:');

      final resolver = buildResolver();
      expect(resolver.resolve(explicit: dir.path), inside);
      expect(discoverySink.toString(), contains('discovered: $inside'));
    });

    test('walk-up discovery finds nearest app root', () {
      // Layout:
      //   <temp>/app/pubspec.yaml
      //   <temp>/app/fastlane/cli_profile.yaml
      //   <temp>/app/lib/src/  ← cwd
      final app = Directory(p.join(tempDir.path, 'app'))
        ..createSync(recursive: true);
      File(p.join(app.path, 'pubspec.yaml')).writeAsStringSync('name: foo');
      final profile = File(p.join(app.path, 'fastlane', 'cli_profile.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('app:');
      final deepCwd = Directory(p.join(app.path, 'lib', 'src'))
        ..createSync(recursive: true);

      final resolver = ProfileResolver(
        environment: const <String, String>{},
        workingDirectory: deepCwd,
        discoverySink: discoverySink,
      );
      expect(resolver.resolve(), profile.path);
      expect(discoverySink.toString(), contains('discovered: ${profile.path}'));
    });

    test('walk-up stops at maxLevels', () {
      // Far-away pubspec — should not be reached with low walk-up budget.
      final far = Directory(p.join(tempDir.path, 'top'))
        ..createSync(recursive: true);
      File(p.join(far.path, 'pubspec.yaml')).writeAsStringSync('name: foo');
      File(p.join(far.path, 'fastlane', 'cli_profile.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('app:');

      // Deep cwd 6 levels below `far`.
      final deep = Directory(p.join(
        far.path,
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ))..createSync(recursive: true);

      final resolver = ProfileResolver(
        environment: const <String, String>{},
        workingDirectory: deep,
        discoverySink: discoverySink,
        walkUpMaxLevels: 2,
      );
      expect(() => resolver.resolve(),
          throwsA(isA<ProfileResolutionException>()));
    });
  });
}
