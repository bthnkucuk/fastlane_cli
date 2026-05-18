import 'dart:io';

import 'package:args/command_runner.dart';

/// `fastlane_cli skills install [--global|--project] [--force] [--dry-run]` —
/// shell wired in Track A2; real copy logic lands in Track C3.
class SkillsCommand extends Command<int> {
  SkillsCommand() {
    addSubcommand(SkillsInstallCommand());
  }

  @override
  String get name => 'skills';

  @override
  String get description => 'Manage the bundled Claude skills directory.';
}

class SkillsInstallCommand extends Command<int> {
  SkillsInstallCommand({StringSink? stdoutSink, StringSink? stderrSink})
    : _stdout = stdoutSink ?? stdout,
      _stderr = stderrSink ?? stderr {
    argParser
      ..addFlag(
        'global',
        defaultsTo: false,
        negatable: false,
        help: 'Install into ~/.claude/skills/.',
      )
      ..addFlag(
        'project',
        defaultsTo: false,
        negatable: false,
        help: 'Install into <cwd>/.claude/skills/ (default).',
      )
      ..addFlag(
        'force',
        defaultsTo: false,
        negatable: false,
        help: 'Overwrite existing skill directories.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        negatable: false,
        help: 'List what would be copied without writing anything.',
      );
  }

  final StringSink _stderr;
  final StringSink _stdout;

  @override
  String get name => 'install';

  @override
  String get description =>
      'Copy the bundled skills/ directory into ~/.claude/skills/ or the project.';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.flag('global') && results.flag('project')) {
      _stderr.writeln('--global and --project are mutually exclusive.');
      return 64;
    }
    _stdout.writeln('TODO: skills install implementation lands in Track C3');
    return 0;
  }
}
