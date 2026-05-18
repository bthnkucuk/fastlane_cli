import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fastlane_cli/src/cli/skills_install_command.dart';
import 'package:fastlane_cli/src/services/runner_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Seeds a fake brew-style layout containing both `fastlane/` and `skills/`
/// next to each other.
({String fastlane, String skills, String binary}) _seedLayout(Directory root) {
  final fastlane = Directory(p.join(root.path, 'fastlane'))
    ..createSync(recursive: true);
  File(p.join(fastlane.path, 'Fastfile')).writeAsStringSync('# stub');

  final skills = Directory(p.join(root.path, 'skills'))
    ..createSync(recursive: true);
  File(p.join(skills.path, 'README.md')).writeAsStringSync('# index');
  Directory(p.join(skills.path, 'demo-skill')).createSync(recursive: true);
  File(p.join(skills.path, 'demo-skill', 'SKILL.md'))
      .writeAsStringSync('demo v1');

  final binDir = Directory(p.join(root.path, 'bin'))
    ..createSync(recursive: true);
  final binary = File(p.join(binDir.path, 'fastlane_cli'))
    ..writeAsStringSync('binary');

  return (
    fastlane: fastlane.path,
    skills: skills.path,
    binary: binary.path,
  );
}

Directory _tempDir(String suffix) {
  final dir = Directory.systemTemp.createTempSync('skills_install_cmd_$suffix');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

({SkillsCommand command, StringBuffer out, StringBuffer err}) _build({
  required String binaryPath,
  required Directory workingDirectory,
  Map<String, String>? environment,
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final command = SkillsCommand(
    runnerResolver: RunnerResolver(
      executablePath: () => binaryPath,
      packageUriResolver: (uri) async => null,
    ),
    stdoutSink: out,
    stderrSink: err,
    environment: environment ?? const <String, String>{},
    workingDirectory: workingDirectory,
  );
  return (command: command, out: out, err: err);
}

void main() {
  group('skills install', () {
    test('rejects --global + --project together', () async {
      final temp = _tempDir('mutex');
      final layout = _seedLayout(temp);
      final harness = _build(
        binaryPath: layout.binary,
        workingDirectory: temp,
      );

      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(harness.command);
      final code = await runner
          .run(<String>['skills', 'install', '--global', '--project']);

      expect(code, 64);
      expect(harness.err.toString(), contains('mutually exclusive'));
    });

    test('--project --dry-run plans against cwd/.claude/skills and writes nothing',
        () async {
      final temp = _tempDir('dry_project');
      final layout = _seedLayout(temp);
      final cwd = Directory(p.join(temp.path, 'project'))
        ..createSync(recursive: true);

      final harness = _build(binaryPath: layout.binary, workingDirectory: cwd);
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(harness.command);
      final code = await runner
          .run(<String>['skills', 'install', '--project', '--dry-run']);

      expect(code, 0);
      final stdout = harness.out.toString();
      expect(stdout, contains('dry-run'));
      expect(stdout, contains('demo-skill'));
      expect(stdout, contains('README.md'));
      expect(stdout, contains('(project)'));
      // Nothing was written to disk.
      expect(
        Directory(p.join(cwd.path, '.claude', 'skills')).existsSync(),
        isFalse,
      );
    });

    test('--project installs into cwd/.claude/skills, re-run skips entries',
        () async {
      final temp = _tempDir('install_project');
      final layout = _seedLayout(temp);
      final cwd = Directory(p.join(temp.path, 'project'))
        ..createSync(recursive: true);

      final harness1 = _build(binaryPath: layout.binary, workingDirectory: cwd);
      final runner1 = CommandRunner<int>('test', 'test')
        ..addCommand(harness1.command);
      final code1 =
          await runner1.run(<String>['skills', 'install', '--project']);

      expect(code1, 0);
      expect(
        File(p.join(cwd.path, '.claude', 'skills', 'demo-skill', 'SKILL.md'))
            .existsSync(),
        isTrue,
      );
      expect(harness1.out.toString(), contains('2 installed'));

      // Second run: idempotent.
      final harness2 = _build(binaryPath: layout.binary, workingDirectory: cwd);
      final runner2 = CommandRunner<int>('test', 'test')
        ..addCommand(harness2.command);
      final code2 =
          await runner2.run(<String>['skills', 'install', '--project']);

      expect(code2, 0);
      final stdout2 = harness2.out.toString();
      expect(stdout2, contains('0 installed'));
      expect(stdout2, contains('2 skipped'));
      expect(stdout2, contains('use --force'));
    });

    test('--force overwrites existing entries', () async {
      final temp = _tempDir('install_force');
      final layout = _seedLayout(temp);
      final cwd = Directory(p.join(temp.path, 'project'))
        ..createSync(recursive: true);

      final h1 = _build(binaryPath: layout.binary, workingDirectory: cwd);
      final r1 = CommandRunner<int>('test', 'test')..addCommand(h1.command);
      await r1.run(<String>['skills', 'install', '--project']);

      // Edit a destination file locally; --force should restore source.
      final target = File(
        p.join(cwd.path, '.claude', 'skills', 'demo-skill', 'SKILL.md'),
      )..writeAsStringSync('local edit');

      final h2 = _build(binaryPath: layout.binary, workingDirectory: cwd);
      final r2 = CommandRunner<int>('test', 'test')..addCommand(h2.command);
      final code =
          await r2.run(<String>['skills', 'install', '--project', '--force']);

      expect(code, 0);
      expect(h2.out.toString(), contains('2 overwritten'));
      expect(target.readAsStringSync(), 'demo v1');
    });

    test('--global without HOME fails clearly', () async {
      final temp = _tempDir('global_no_home');
      final layout = _seedLayout(temp);
      final harness = _build(
        binaryPath: layout.binary,
        workingDirectory: temp,
        environment: const <String, String>{},
      );
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(harness.command);
      final code = await runner.run(<String>['skills', 'install', '--global']);

      expect(code, 1);
      expect(harness.err.toString(), contains('HOME'));
    });

    test('--global targets \$HOME/.claude/skills', () async {
      final temp = _tempDir('global');
      final layout = _seedLayout(temp);
      final home = Directory(p.join(temp.path, 'home'))
        ..createSync(recursive: true);

      final harness = _build(
        binaryPath: layout.binary,
        workingDirectory: temp,
        environment: <String, String>{'HOME': home.path},
      );
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(harness.command);
      final code = await runner.run(<String>['skills', 'install', '--global']);

      expect(code, 0);
      expect(harness.out.toString(), contains('(global)'));
      expect(
        File(p.join(home.path, '.claude', 'skills', 'demo-skill', 'SKILL.md'))
            .existsSync(),
        isTrue,
      );
    });

    test('reports clear error when skills/ sibling is missing', () async {
      final temp = _tempDir('no_skills');
      // Seed only fastlane/, NOT skills/.
      final fastlane = Directory(p.join(temp.path, 'fastlane'))
        ..createSync(recursive: true);
      File(p.join(fastlane.path, 'Fastfile')).writeAsStringSync('# stub');
      final binDir = Directory(p.join(temp.path, 'bin'))
        ..createSync(recursive: true);
      final binary = File(p.join(binDir.path, 'fastlane_cli'))
        ..writeAsStringSync('binary');

      final cwd = Directory(p.join(temp.path, 'project'))
        ..createSync(recursive: true);
      final harness = _build(binaryPath: binary.path, workingDirectory: cwd);
      final runner = CommandRunner<int>('test', 'test')
        ..addCommand(harness.command);
      final code = await runner
          .run(<String>['skills', 'install', '--project', '--dry-run']);

      expect(code, 1);
      expect(
        harness.err.toString(),
        contains('skills/ directory not found'),
      );
    });
  });
}
