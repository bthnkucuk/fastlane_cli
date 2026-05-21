import 'dart:io';

import 'package:fastlane_cli/src/services/skills_installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Materialises a fake bundled `skills/` source tree under [root].
///
/// Layout:
/// ```
/// <root>/skills/
///   README.md
///   skill-a/SKILL.md
///   skill-b/SKILL.md
///   skill-b/nested/notes.md
/// ```
String _seedSourceSkills(Directory root) {
  final source = Directory(p.join(root.path, 'skills'))
    ..createSync(recursive: true);
  File(p.join(source.path, 'README.md')).writeAsStringSync('# skills index');

  final skillA = Directory(p.join(source.path, 'skill-a'))
    ..createSync(recursive: true);
  File(p.join(skillA.path, 'SKILL.md')).writeAsStringSync('skill-a v1');

  final skillB = Directory(p.join(source.path, 'skill-b'))
    ..createSync(recursive: true);
  File(p.join(skillB.path, 'SKILL.md')).writeAsStringSync('skill-b v1');
  Directory(p.join(skillB.path, 'nested')).createSync(recursive: true);
  File(p.join(skillB.path, 'nested', 'notes.md')).writeAsStringSync('notes');

  return source.path;
}

Directory _tempDir(String suffix) {
  final dir = Directory.systemTemp.createTempSync('skills_installer_$suffix');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

void main() {
  group('SkillsInstaller.plan', () {
    test('lists every skill subdir + README on a clean destination', () {
      final temp = _tempDir('plan_clean');
      final source = _seedSourceSkills(temp);
      final destination = p.join(temp.path, '.claude', 'skills');

      final plan = const SkillsInstaller().plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
      );

      expect(plan.entries.map((e) => e.name).toList(),
          <String>['README.md', 'skill-a', 'skill-b']);
      expect(plan.entries.every((e) => e.action == SkillAction.install),
          isTrue);
      expect(plan.destinationLabel, 'project');
      expect(plan.source, p.absolute(source));
      expect(plan.destination, p.absolute(destination));
    });

    test('marks existing entries as skip without --force', () {
      final temp = _tempDir('plan_skip');
      final source = _seedSourceSkills(temp);
      final destination = p.join(temp.path, '.claude', 'skills');

      // Pre-create skill-a so it appears as a skip.
      Directory(p.join(destination, 'skill-a')).createSync(recursive: true);
      File(p.join(destination, 'skill-a', 'SKILL.md'))
          .writeAsStringSync('preexisting');

      final plan = const SkillsInstaller().plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
      );

      final byName = {for (final e in plan.entries) e.name: e};
      expect(byName['skill-a']!.action, SkillAction.skip);
      expect(byName['skill-b']!.action, SkillAction.install);
      expect(byName['README.md']!.action, SkillAction.install);
    });

    test('marks existing entries as overwrite with --force', () {
      final temp = _tempDir('plan_force');
      final source = _seedSourceSkills(temp);
      final destination = p.join(temp.path, '.claude', 'skills');
      Directory(p.join(destination, 'skill-a')).createSync(recursive: true);

      final plan = const SkillsInstaller().plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'global',
        force: true,
      );

      final byName = {for (final e in plan.entries) e.name: e};
      expect(byName['skill-a']!.action, SkillAction.overwrite);
      expect(byName['skill-b']!.action, SkillAction.install);
    });

    test('throws when source directory does not exist', () {
      final temp = _tempDir('plan_missing_source');
      expect(
        () => const SkillsInstaller().plan(
          sourceDir: p.join(temp.path, 'nope'),
          destinationDir: p.join(temp.path, 'dst'),
          destinationLabel: 'project',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SkillsInstaller.install', () {
    test('copies every entry recursively on first run', () async {
      final temp = _tempDir('install_clean');
      final source = _seedSourceSkills(temp);
      final destination = p.join(temp.path, '.claude', 'skills');

      const installer = SkillsInstaller();
      final plan = installer.plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
      );
      final report = await installer.install(plan);

      expect(report.installed, 3);
      expect(report.skipped, 0);
      expect(report.overwritten, 0);
      expect(report.errors, 0);

      expect(File(p.join(destination, 'README.md')).existsSync(), isTrue);
      expect(File(p.join(destination, 'skill-a', 'SKILL.md')).existsSync(),
          isTrue);
      expect(
        File(p.join(destination, 'skill-b', 'nested', 'notes.md')).existsSync(),
        isTrue,
      );
    });

    test('re-running without --force skips and leaves existing untouched',
        () async {
      final temp = _tempDir('install_idempotent');
      final source = _seedSourceSkills(temp);
      final destination = p.join(temp.path, '.claude', 'skills');

      const installer = SkillsInstaller();
      await installer.install(installer.plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
      ));

      // Mutate a destination file to prove the second pass does not touch it.
      final touched = File(p.join(destination, 'skill-a', 'SKILL.md'))
        ..writeAsStringSync('local edit');

      final report2 = await installer.install(installer.plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
      ));

      expect(report2.installed, 0);
      expect(report2.skipped, 3);
      expect(report2.overwritten, 0);
      expect(touched.readAsStringSync(), 'local edit');
    });

    test('--force overwrites existing entries on disk', () async {
      final temp = _tempDir('install_force');
      final source = _seedSourceSkills(temp);
      final destination = p.join(temp.path, '.claude', 'skills');

      const installer = SkillsInstaller();
      await installer.install(installer.plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
      ));
      File(p.join(destination, 'skill-a', 'SKILL.md'))
          .writeAsStringSync('local edit');

      final report = await installer.install(installer.plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
        force: true,
      ));

      expect(report.installed, 0);
      expect(report.overwritten, 3);
      expect(
        File(p.join(destination, 'skill-a', 'SKILL.md')).readAsStringSync(),
        'skill-a v1',
      );
    });

    test('removes stale files inside an overwritten skill directory',
        () async {
      final temp = _tempDir('install_stale');
      final source = _seedSourceSkills(temp);
      final destination = p.join(temp.path, '.claude', 'skills');

      const installer = SkillsInstaller();
      await installer.install(installer.plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
      ));

      // Add a stale file that does not exist in source. It must be wiped on
      // --force overwrite.
      final stale = File(p.join(destination, 'skill-a', 'stale.txt'))
        ..writeAsStringSync('gone');

      await installer.install(installer.plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
        force: true,
      ));

      expect(stale.existsSync(), isFalse);
    });

    test('surfaces per-entry I/O errors without aborting the batch', () async {
      final temp = _tempDir('install_error');
      final source = _seedSourceSkills(temp);
      final destination = p.join(temp.path, '.claude', 'skills');

      // Sabotage the source for skill-b: delete it after planning.
      final installer = const SkillsInstaller();
      final plan = installer.plan(
        sourceDir: source,
        destinationDir: destination,
        destinationLabel: 'project',
      );
      Directory(p.join(source, 'skill-b')).deleteSync(recursive: true);

      final report = await installer.install(plan);

      expect(report.errors, greaterThanOrEqualTo(1));
      expect(report.installed, greaterThanOrEqualTo(1));
      // Healthy entries still landed.
      expect(File(p.join(destination, 'README.md')).existsSync(), isTrue);
      expect(
        File(p.join(destination, 'skill-a', 'SKILL.md')).existsSync(),
        isTrue,
      );
    });
  });
}
