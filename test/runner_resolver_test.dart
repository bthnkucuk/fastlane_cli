import 'dart:io';

import 'package:fastlane_cli/src/services/runner_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Creates a minimally-valid fastlane runner directory (just a `Fastfile`)
/// at [path] and returns the absolute path.
String _seedFastlaneDir(String path) {
  final dir = Directory(path)..createSync(recursive: true);
  File(p.join(dir.path, 'Fastfile')).writeAsStringSync('# stub');
  return dir.absolute.path;
}

/// A throwaway directory each test cleans up on exit.
Directory _tempDir(String suffix) {
  final dir = Directory.systemTemp.createTempSync('runner_resolver_$suffix');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  group('RunnerResolver', () {
    test('honours an explicit profile override pointing at a fastlane dir',
        () async {
      final temp = _tempDir('override');
      final fastlane = _seedFastlaneDir(p.join(temp.path, 'fastlane'));

      // Resolver where every fallback branch would fail. If it returns the
      // override, we know branch (1) ran without falling through.
      final resolver = RunnerResolver(
        executablePath: () => p.join(temp.path, 'no-such-binary'),
        packageUriResolver: (uri) async => null,
      );

      final resolved = await resolver.resolve(profileOverride: fastlane);
      expect(resolved, fastlane);
    });

    test('falls through when override is empty / whitespace', () async {
      final temp = _tempDir('override_empty');
      final fastlane = _seedFastlaneDir(p.join(temp.path, 'fastlane'));
      // Simulate brew layout for the executable walk branch.
      final prefix = Directory(p.join(temp.path, 'prefix'))
        ..createSync(recursive: true);
      final binDir = Directory(p.join(prefix.path, 'bin'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(binDir.path, 'fastlane_cli'))
        ..writeAsStringSync('binary');
      _seedFastlaneDir(p.join(prefix.path, 'share', 'fastlane_cli', 'fastlane'));

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => null,
      );

      final resolved = await resolver.resolve(profileOverride: '   ');
      expect(
        resolved,
        p.normalize(
          p.join(prefix.path, 'share', 'fastlane_cli', 'fastlane'),
        ),
      );
      // The override path itself should NOT be returned because resolver
      // requires a Fastfile, but the value is also a valid fastlane dir.
      // Sanity: returned path is the share/ candidate, not the override.
      expect(resolved, isNot(fastlane));
    });

    test('walks up from executable to find brew share layout', () async {
      final temp = _tempDir('brew');
      final prefix = Directory(p.join(temp.path, 'opt', 'fastlane_cli'))
        ..createSync(recursive: true);
      final binDir = Directory(p.join(prefix.path, 'bin'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(binDir.path, 'fastlane_cli'))
        ..writeAsStringSync('binary');
      final expected = _seedFastlaneDir(
        p.join(prefix.path, 'share', 'fastlane_cli', 'fastlane'),
      );

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        // Force packageUri branch to be unavailable.
        packageUriResolver: (uri) async => null,
      );

      final resolved = await resolver.resolve();
      expect(resolved, expected);
    });

    test('walks up from executable to find source repo layout', () async {
      final temp = _tempDir('source');
      // Mirrors `<repo>/build/fastlane_cli` next to `<repo>/fastlane/`.
      final repo = Directory(p.join(temp.path, 'repo'))
        ..createSync(recursive: true);
      final buildDir = Directory(p.join(repo.path, 'build'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(buildDir.path, 'fastlane_cli'))
        ..writeAsStringSync('binary');
      final expected = _seedFastlaneDir(p.join(repo.path, 'fastlane'));

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => null,
      );

      final resolved = await resolver.resolve();
      expect(resolved, expected);
    });

    test('falls back to package URI resolution when executable walk misses',
        () async {
      final temp = _tempDir('package_uri');
      // Place the binary somewhere with no nearby fastlane/ tree.
      final isolated = Directory(p.join(temp.path, 'isolated'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(isolated.path, 'binary'))
        ..writeAsStringSync('binary');

      // Mimic what `Isolate.resolvePackageUri` returns: a `file://` URI under
      // <repo>/lib/. The resolver then resolves '../fastlane/' relative to it.
      final repo = Directory(p.join(temp.path, 'repo'))
        ..createSync(recursive: true);
      final libDir = Directory(p.join(repo.path, 'lib'))
        ..createSync(recursive: true);
      final packageUriTarget = File(p.join(libDir.path, '_dummy.dart'));
      final expected = _seedFastlaneDir(p.join(repo.path, 'fastlane'));

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => packageUriTarget.uri,
      );

      final resolved = await resolver.resolve();
      expect(resolved, expected);
    });

    test('throws StateError listing every tried path when nothing matches',
        () async {
      final temp = _tempDir('miss');
      final isolated = Directory(p.join(temp.path, 'isolated'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(isolated.path, 'binary'))
        ..writeAsStringSync('binary');

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => null,
      );

      await expectLater(
        resolver.resolve(profileOverride: p.join(temp.path, 'nope')),
        throwsA(
          predicate<StateError>(
            (error) =>
                error.message.contains('fastlane runner not found') &&
                error.message.contains('profile override') &&
                error.message.contains('executable walk') &&
                error.message.contains('package uri'),
          ),
        ),
      );
    });

    test('reports packageUriResolver errors in the diagnostic path list',
        () async {
      final temp = _tempDir('pkg_error');
      final isolated = Directory(p.join(temp.path, 'isolated'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(isolated.path, 'binary'))
        ..writeAsStringSync('binary');

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => throw StateError('isolate down'),
      );

      await expectLater(
        resolver.resolve(),
        throwsA(
          predicate<StateError>(
            (error) =>
                error.message.contains('fastlane runner not found') &&
                error.message.contains('<error: '),
          ),
        ),
      );
    });

    test('an empty directory (no Fastfile) does NOT satisfy resolution',
        () async {
      // A `fastlane/` dir without a Fastfile is unusable — the resolver must
      // skip it and fall through to the structured StateError.
      final temp = _tempDir('empty_dir');
      final emptyFastlane = Directory(p.join(temp.path, 'fastlane'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(temp.path, 'binary'))
        ..writeAsStringSync('binary');

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => null,
      );

      await expectLater(
        resolver.resolve(profileOverride: emptyFastlane.path),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('RunnerResolver.resolveSkillsDirectory', () {
    test('returns the skills/ sibling of a resolved runner', () async {
      final temp = _tempDir('skills_ok');
      final repo = Directory(p.join(temp.path, 'repo'))
        ..createSync(recursive: true);
      _seedFastlaneDir(p.join(repo.path, 'fastlane'));
      final skills = Directory(p.join(repo.path, 'skills'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(repo.path, 'fastlane_cli'))
        ..writeAsStringSync('binary');

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => null,
      );

      final resolved = await resolver.resolveSkillsDirectory();
      expect(resolved, p.normalize(skills.path));
    });

    test('honours a profile override when resolving the skills sibling',
        () async {
      final temp = _tempDir('skills_override');
      final repo = Directory(p.join(temp.path, 'repo'))
        ..createSync(recursive: true);
      final fastlane = _seedFastlaneDir(p.join(repo.path, 'fastlane'));
      Directory(p.join(repo.path, 'skills')).createSync(recursive: true);

      // Every fallback branch fails — only the override can resolve.
      final resolver = RunnerResolver(
        executablePath: () => p.join(temp.path, 'no-such-binary'),
        packageUriResolver: (uri) async => null,
      );

      final resolved =
          await resolver.resolveSkillsDirectory(profileOverride: fastlane);
      expect(resolved, p.normalize(p.join(repo.path, 'skills')));
    });

    test('throws StateError when the runner resolves but skills/ is absent',
        () async {
      final temp = _tempDir('skills_missing');
      final repo = Directory(p.join(temp.path, 'repo'))
        ..createSync(recursive: true);
      // Runner exists, but no sibling skills/ directory.
      _seedFastlaneDir(p.join(repo.path, 'fastlane'));
      final fakeBinary = File(p.join(repo.path, 'fastlane_cli'))
        ..writeAsStringSync('binary');

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => null,
      );

      await expectLater(
        resolver.resolveSkillsDirectory(),
        throwsA(
          predicate<StateError>(
            (error) =>
                error.message.contains('skills/ directory not found') &&
                error.message.contains('expected:'),
          ),
        ),
      );
    });

    test('propagates the runner StateError when nothing resolves', () async {
      final temp = _tempDir('skills_no_runner');
      final isolated = Directory(p.join(temp.path, 'isolated'))
        ..createSync(recursive: true);
      final fakeBinary = File(p.join(isolated.path, 'binary'))
        ..writeAsStringSync('binary');

      final resolver = RunnerResolver(
        executablePath: fakeBinary.path.toString,
        packageUriResolver: (uri) async => null,
      );

      await expectLater(
        resolver.resolveSkillsDirectory(),
        throwsA(
          predicate<StateError>(
            (error) => error.message.contains('fastlane runner not found'),
          ),
        ),
      );
    });
  });
}
