import 'dart:io';

import 'package:args/command_runner.dart';

import '../model/cli_action.dart';
import '../services/command_builder.dart';
import '../services/command_execution_service.dart';
import '../services/profile_loader.dart';
import 'profile_resolver.dart';

/// `fastlane_cli run <action-id> [--option key=value ...]` —
/// headless lane execution. Streams logs to stdout/stderr in plain form and
/// propagates the lane's exit code.
class RunCommand extends Command<int> {
  RunCommand({
    ProfileLoader? profileLoader,
    CommandBuilder? commandBuilder,
    CommandExecutionService? executionService,
    ProfileResolver? profileResolver,
    StringSink? stdoutSink,
    StringSink? stderrSink,
  }) : _profileLoader = profileLoader ?? const ProfileLoader(),
       _commandBuilder = commandBuilder ?? const CommandBuilder(),
       _executionService =
           executionService ?? const ProcessCommandExecutionService(),
       _profileResolver = profileResolver ?? const ProfileResolver(),
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr {
    argParser
      ..addOption(
        'profile',
        abbr: 'p',
        help: 'Path to cli_profile.yaml',
      )
      ..addMultiOption(
        'option',
        abbr: 'o',
        help: 'Override a command option (key=value), repeatable.',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        negatable: false,
        help: 'Print the resolved command without executing it.',
      );
  }

  final ProfileLoader _profileLoader;
  final CommandBuilder _commandBuilder;
  final CommandExecutionService _executionService;
  final ProfileResolver _profileResolver;
  final StringSink _stdout;
  final StringSink _stderr;

  @override
  String get name => 'run';

  @override
  String get description =>
      'Run a profile action by id non-interactively.';

  @override
  String get invocation =>
      'fastlane_cli run <action-id> [--option key=value ...]';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.isEmpty) {
      _stderr.writeln('Missing required <action-id>.');
      _stderr.writeln(usage);
      return 64;
    }
    if (results.rest.length > 1) {
      _stderr.writeln(
        'Expected a single <action-id>, got: ${results.rest.join(' ')}',
      );
      return 64;
    }
    final actionId = results.rest.single;

    final String profilePath;
    try {
      profilePath = _profileResolver.resolve(
        explicit: results.option('profile'),
      );
    } on ProfileResolutionException catch (error) {
      _stderr.writeln(error.toString());
      return 66;
    }

    final overrides = _parseOverrides(results.multiOption('option'));
    if (overrides == null) {
      return 64;
    }

    final profile = await _profileLoader.load(profilePath);
    final base = profile.actionsById[actionId];
    if (base == null) {
      _stderr.writeln('Unknown action id: $actionId');
      _stderr.writeln(
        'Run `fastlane_cli list` to see available actions.',
      );
      return 64;
    }

    final action = overrides.isEmpty
        ? base
        : _withMergedOptions(base, overrides);

    final request = _commandBuilder.build(profile: profile, action: action);
    final dryRun = results.flag('dry-run');

    final result = await _executionService.run(
      request,
      dryRun: dryRun,
      onLog: (event) {
        final sink = event.isError ? _stderr : _stdout;
        sink.writeln(event.message);
      },
    );
    return result.exitCode;
  }

  Map<String, String>? _parseOverrides(List<String> raw) {
    final out = <String, String>{};
    for (final entry in raw) {
      final idx = entry.indexOf('=');
      if (idx <= 0) {
        _stderr.writeln(
          'Invalid --option "$entry"; expected key=value.',
        );
        return null;
      }
      out[entry.substring(0, idx).trim()] = entry.substring(idx + 1);
    }
    return out;
  }

  CliAction _withMergedOptions(CliAction base, Map<String, String> overrides) {
    if (base.command.type != ActionCommandType.fastlane) {
      // Only fastlane supports key:value options today; for other command
      // types we leave the base action untouched.
      return base;
    }
    return CliAction(
      id: base.id,
      categoryId: base.categoryId,
      title: base.title,
      description: base.description,
      command: CliActionCommand(
        type: base.command.type,
        platform: base.command.platform,
        lane: base.command.lane,
        options: <String, String>{...base.command.options, ...overrides},
        arguments: base.command.arguments,
        executable: base.command.executable,
      ),
      preflightChecks: base.preflightChecks,
      shortcut: base.shortcut,
      requiresConfirmation: base.requiresConfirmation,
      requiresOverwriteConfirmation: base.requiresOverwriteConfirmation,
    );
  }
}
