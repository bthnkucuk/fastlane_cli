import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fastlane_cli/src/cli/init_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('InitCommand', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('init_cmd_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<({int exit, String stdout, String stderr, String? written})>
        runInit(List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final command = InitCommand(
        workingDirectory: tempDir,
        stdoutSink: out,
        stderrSink: err,
      );
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);
      final code = await runner.run(<String>['init', ...args]);
      final target = File(p.join(tempDir.path, 'profile.yaml'));
      return (
        exit: code ?? 0,
        stdout: out.toString(),
        stderr: err.toString(),
        written: target.existsSync() ? target.readAsStringSync() : null,
      );
    }

    test('writes minimal profile.yaml in cwd', () async {
      final result = await runInit(const <String>['--app-name', 'demo']);
      expect(result.exit, 0);
      expect(result.written, isNotNull);
      expect(result.written, contains('name: demo'));
      expect(result.written, contains('root_path:'));
      expect(result.written, contains('default_locale:'));
    });

    test('refuses to overwrite without --force', () async {
      final target = File(p.join(tempDir.path, 'profile.yaml'))
        ..writeAsStringSync('# existing');

      final result = await runInit(const <String>[]);
      expect(result.exit, 73);
      expect(result.stderr, contains('--force'));
      expect(target.readAsStringSync(), '# existing');
    });

    test('overwrites with --force', () async {
      File(p.join(tempDir.path, 'profile.yaml'))
          .writeAsStringSync('# old');

      final result = await runInit(const <String>['--force']);
      expect(result.exit, 0);
      expect(result.written, contains('app:'));
      expect(result.written, isNot(contains('# old')));
    });

    test('--platform ios omits the android hint', () async {
      final result =
          await runInit(const <String>['--platform', 'ios', '--force']);
      expect(result.exit, 0);
      expect(result.written, isNot(contains('Android lanes')));
      expect(result.written, contains('iOS lanes'));
    });

    test('--platform android omits the ios hint', () async {
      final result =
          await runInit(const <String>['--platform', 'android', '--force']);
      expect(result.exit, 0);
      expect(result.written, contains('Android lanes'));
      expect(result.written, isNot(contains('iOS lanes')));
    });
  });
}
