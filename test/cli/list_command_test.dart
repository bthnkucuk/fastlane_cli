import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/profile_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/profile_factory.dart';

void main() {
  group('ListCommand', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('list_cmd_');
      // Provide a discoverable profile file so the resolver succeeds; the
      // actual contents are ignored because we inject _StaticLoader.
      File(p.join(tempDir.path, 'cli_profile.yaml'))
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
          makeCategory(id: 'ios', actionIds: <String>['i1']),
        ],
        actions: <CliAction>[
          makeFastlaneAction(id: 'a1', categoryId: 'android', lane: 'la'),
          makeFastlaneAction(id: 'i1', categoryId: 'ios', lane: 'li'),
        ],
      );
    }

    Future<({int exit, String stdout, String stderr})> runList(
      List<String> args,
      CliProfile profile,
    ) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final command = ListCommand(
        profileLoader: _StaticLoader(profile),
        profileResolver: ProfileResolver(workingDirectory: tempDir),
        stdoutSink: out,
        stderrSink: err,
      );
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);
      final code = await runner.run(<String>['list', ...args]);
      return (exit: code ?? 0, stdout: out.toString(), stderr: err.toString());
    }

    test('--json emits valid JSON with id/title/description/category',
        () async {
      final result = await runList(<String>['--json'], buildProfile());
      expect(result.exit, 0);

      final decoded = jsonDecode(result.stdout.trim()) as List<dynamic>;
      expect(decoded, hasLength(2));
      final first = decoded.first as Map<String, dynamic>;
      expect(
        first.keys,
        containsAll(<String>['id', 'title', 'description', 'category']),
      );
      expect(first['id'], 'a1');
      expect(first['category'], 'android');
    });

    test('--category filters output', () async {
      final result =
          await runList(<String>['--json', '--category', 'android'], buildProfile());
      expect(result.exit, 0);
      final decoded = jsonDecode(result.stdout.trim()) as List<dynamic>;
      expect(decoded, hasLength(1));
      expect((decoded.single as Map<String, dynamic>)['id'], 'a1');
    });

    test('plain text mode prints id and title per action', () async {
      final result = await runList(const <String>[], buildProfile());
      expect(result.exit, 0);
      expect(result.stdout, contains('a1'));
      expect(result.stdout, contains('i1'));
      expect(result.stdout, contains('[android]'));
    });

    test('empty category prints friendly message', () async {
      final result =
          await runList(<String>['--category', 'unknown'], buildProfile());
      expect(result.exit, 0);
      expect(result.stdout, contains('No actions in category "unknown"'));
    });
  });
}

class _StaticLoader extends ProfileLoader {
  _StaticLoader(this._profile);

  final CliProfile _profile;

  @override
  Future<CliProfile> load(String profilePath) async => _profile;
}
