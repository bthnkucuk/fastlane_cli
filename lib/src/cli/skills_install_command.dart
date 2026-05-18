import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../services/runner_resolver.dart';
import '../services/skills_installer.dart';

/// `fastlane_cli skills install [--global|--project] [--force] [--dry-run]` —
/// copies the bundled Claude `skills/` tree into either `<cwd>/.claude/skills/`
/// (default) or `$HOME/.claude/skills/` (`--global`).
class SkillsCommand extends Command<int> {
  SkillsCommand({
    RunnerResolver? runnerResolver,
    SkillsInstaller? installer,
    StringSink? stdoutSink,
    StringSink? stderrSink,
    Map<String, String>? environment,
    Directory? workingDirectory,
  }) {
    addSubcommand(
      SkillsInstallCommand(
        runnerResolver: runnerResolver,
        installer: installer,
        stdoutSink: stdoutSink,
        stderrSink: stderrSink,
        environment: environment,
        workingDirectory: workingDirectory,
      ),
    );
  }

  @override
  String get name => 'skills';

  @override
  String get description => 'Manage the bundled Claude skills directory.';
}

class SkillsInstallCommand extends Command<int> {
  SkillsInstallCommand({
    RunnerResolver? runnerResolver,
    SkillsInstaller? installer,
    StringSink? stdoutSink,
    StringSink? stderrSink,
    Map<String, String>? environment,
    Directory? workingDirectory,
  })  : _runnerResolver = runnerResolver ?? const RunnerResolver(),
        _installer = installer ?? const SkillsInstaller(),
        _stdout = stdoutSink ?? stdout,
        _stderr = stderrSink ?? stderr,
        _environment = environment ?? Platform.environment,
        _workingDirectory = workingDirectory ?? Directory.current {
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

  final RunnerResolver _runnerResolver;
  final SkillsInstaller _installer;
  final StringSink _stdout;
  final StringSink _stderr;
  final Map<String, String> _environment;
  final Directory _workingDirectory;

  @override
  String get name => 'install';

  @override
  String get description =>
      'Copy the bundled skills/ directory into ~/.claude/skills/ or the project.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final globalFlag = results.flag('global');
    final projectFlag = results.flag('project');
    final force = results.flag('force');
    final dryRun = results.flag('dry-run');

    if (globalFlag && projectFlag) {
      _stderr.writeln('--global and --project are mutually exclusive.');
      return 64;
    }

    final isGlobal = globalFlag;
    final String destinationDir;
    final String destinationLabel;
    if (isGlobal) {
      final home = _environment['HOME'];
      if (home == null || home.trim().isEmpty) {
        _stderr.writeln(
          'Cannot resolve global skills destination: HOME is not set.',
        );
        return 1;
      }
      destinationDir = p.join(home, '.claude', 'skills');
      destinationLabel = 'global';
    } else {
      destinationDir =
          p.join(_workingDirectory.absolute.path, '.claude', 'skills');
      destinationLabel = 'project';
    }

    final String sourceDir;
    try {
      sourceDir = await _runnerResolver.resolveSkillsDirectory();
    } on StateError catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

    final InstallPlan plan;
    try {
      plan = _installer.plan(
        sourceDir: sourceDir,
        destinationDir: destinationDir,
        destinationLabel: destinationLabel,
        force: force,
      );
    } on StateError catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

    _writeHeader(plan, dryRun: dryRun);

    final List<SkillEntry> finalEntries;
    if (dryRun) {
      finalEntries = plan.entries;
    } else {
      final report = await _installer.install(plan);
      finalEntries = report.entries;
    }

    for (final entry in finalEntries) {
      _writeEntry(entry);
    }

    _writeFooter(finalEntries, dryRun: dryRun);

    final hasErrors = finalEntries.any((e) => e.action == SkillAction.error);
    return hasErrors ? 1 : 0;
  }

  void _writeHeader(InstallPlan plan, {required bool dryRun}) {
    _stdout.writeln('fastlane_cli skills install${dryRun ? ' (dry-run)' : ''}');
    _stdout.writeln('  source:      ${plan.source}');
    _stdout.writeln(
      '  destination: ${plan.destination} (${plan.destinationLabel})',
    );
    _stdout.writeln('');
  }

  void _writeEntry(SkillEntry entry) {
    final marker = _markerFor(entry.action);
    switch (entry.action) {
      case SkillAction.install:
        _stdout.writeln('  $marker ${entry.name}');
      case SkillAction.overwrite:
        _stdout.writeln('  $marker ${entry.name} (overwritten)');
      case SkillAction.skip:
        _stdout.writeln(
          '  $marker ${entry.name} (already exists; use --force to overwrite)',
        );
      case SkillAction.error:
        final msg = entry.errorMessage ?? 'unknown error';
        _stdout.writeln('  $marker ${entry.name} (error: $msg)');
    }
  }

  void _writeFooter(List<SkillEntry> entries, {required bool dryRun}) {
    final installed =
        entries.where((e) => e.action == SkillAction.install).length;
    final skipped = entries.where((e) => e.action == SkillAction.skip).length;
    final overwritten =
        entries.where((e) => e.action == SkillAction.overwrite).length;
    final errors = entries.where((e) => e.action == SkillAction.error).length;

    _stdout.writeln('');
    final prefix = dryRun ? 'plan: ' : '';
    final parts = <String>[
      '$installed installed',
      '$skipped skipped',
      '$overwritten overwritten',
    ];
    if (errors > 0) {
      parts.add('$errors error${errors == 1 ? '' : 's'}');
    }
    _stdout.writeln('$prefix${parts.join(' · ')}');
  }

  String _markerFor(SkillAction action) {
    // ANSI colour codes only when stdout is a terminal; the StringSink case
    // (tests, captured output) gets the plain markers.
    final colour = identical(_stdout, stdout) && stdout.hasTerminal;
    String wrap(String code, String text) =>
        colour ? '[${code}m$text[0m' : text;
    switch (action) {
      case SkillAction.install:
        return wrap('32', '[+]'); // green
      case SkillAction.skip:
        return wrap('33', '[~]'); // yellow
      case SkillAction.overwrite:
        return wrap('34', '[*]'); // blue
      case SkillAction.error:
        return wrap('31', '[!]'); // red
    }
  }
}
