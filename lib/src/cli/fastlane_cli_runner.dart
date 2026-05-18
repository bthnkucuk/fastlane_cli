import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../bootstrap/fastlane_cli_launcher.dart';
import 'completion_command.dart';
import 'doctor_command.dart';
import 'init_command.dart';
import 'list_command.dart';
import 'run_command.dart';
import 'skills_install_command.dart';

/// Top-level `CommandRunner` for the `fastlane_cli` binary.
///
/// Wires every subcommand class under `lib/src/cli/`. When no subcommand is
/// passed (the legacy invocation), delegates to [FastlaneCliLauncher] so the
/// TUI keeps working exactly as it did before Wave 2 / Track A2.
class FastlaneCliRunner extends CommandRunner<int> {
  FastlaneCliRunner({FastlaneCliLauncher? launcher})
    : _launcher = launcher ?? FastlaneCliLauncher(),
      super(
        'fastlane_cli',
        'Terminal-first Fastlane assistant for Flutter projects.',
      ) {
    // Mirror the legacy top-level flags so `fastlane_cli --profile <p>` still
    // works without a subcommand.
    argParser
      ..addOption('profile', abbr: 'p', help: 'Path to cli_profile.yaml')
      ..addOption(
        'lang',
        allowed: const <String>['tr', 'en'],
        help: 'Language override (legacy top-level flag).',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        negatable: false,
        help: 'Build command and stream logs without execution.',
      );

    addCommand(RunCommand());
    addCommand(ListCommand());
    addCommand(InitCommand());
    addCommand(DoctorCommand());
    addCommand(SkillsCommand());
    addCommand(CompletionCommand());
  }

  final FastlaneCliLauncher _launcher;

  @override
  Future<int> run(Iterable<String> args) async {
    final argList = args.toList(growable: false);

    // Detect "no subcommand was given" → delegate to the TUI launcher. We
    // can't rely on argResults.command here because top-level flags
    // (`--profile`, `--lang`, `--dry-run`) are valid both for the TUI and as
    // a precursor to a real subcommand. So we look for the first non-flag,
    // non-flag-value token and check whether it matches a known subcommand.
    if (_shouldDelegateToTui(argList)) {
      return _launcher.run(argList);
    }

    try {
      final result = await super.run(argList);
      return result ?? 0;
    } on UsageException catch (error) {
      stderr.writeln(error.message);
      stderr.writeln(error.usage);
      return 64;
    } on FormatException catch (error) {
      stderr.writeln('Invalid input: ${error.message}');
      return 64;
    }
  }

  bool _shouldDelegateToTui(List<String> args) {
    if (args.isEmpty) {
      return true;
    }

    // Top-level flags we accept before "no subcommand" is decided.
    const valueFlags = <String>{'--profile', '-p', '--lang'};
    const boolFlags = <String>{
      '--dry-run',
      '--help',
      '-h',
      '--version',
    };

    final subcommandNames = commands.keys.toSet();

    var i = 0;
    while (i < args.length) {
      final token = args[i];
      if (token == '--') {
        // Everything after `--` is positional for the TUI.
        return true;
      }
      if (token.startsWith('-')) {
        // Argument with `=` is self-contained.
        if (token.contains('=')) {
          i++;
          continue;
        }
        if (valueFlags.contains(token)) {
          i += 2;
          continue;
        }
        if (boolFlags.contains(token)) {
          // `--help` at top-level is a CommandRunner concern; let super.run
          // handle it so users get the subcommand listing.
          if (token == '--help' || token == '-h' || token == '--version') {
            return false;
          }
          i++;
          continue;
        }
        // Unknown flag → let CommandRunner produce the error.
        return false;
      }

      // First positional token: if it's a known subcommand, do not delegate.
      return !subcommandNames.contains(token);
    }
    // Only top-level flags, no positional → TUI mode.
    return true;
  }
}

/// Top-level `ArgParser` so callers (e.g. integration tests) can inspect the
/// flag layout without spinning up a full runner.
ArgParser buildTopLevelParser() {
  return ArgParser()
    ..addOption('profile', abbr: 'p')
    ..addOption('lang', allowed: const <String>['tr', 'en'])
    ..addFlag('dry-run', defaultsTo: false, negatable: false)
    ..addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
}
