import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../bootstrap/fastlane_cli_launcher.dart';
import '../version.dart';
import 'completion_command.dart';
import 'doctor_command.dart';
import 'init_command.dart';
import 'list_command.dart';
import 'profile_resolver.dart';
import 'run_command.dart';
import 'skills_install_command.dart';

/// Top-level `CommandRunner` for the `fastlane_cli` binary.
///
/// Wires every subcommand class under `lib/src/cli/`. When no subcommand is
/// passed (the legacy invocation), delegates to [FastlaneCliLauncher] so the
/// TUI keeps working exactly as it did before Wave 2 / Track A2.
class FastlaneCliRunner extends CommandRunner<int> {
  FastlaneCliRunner({FastlaneCliLauncher? launcher, StringSink? stdoutSink})
    : _launcher =
          launcher ?? FastlaneCliLauncher(resolver: const ProfileResolver()),
      _stdoutSink = stdoutSink,
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
      )
      // Short alias `-v` is free (no other top-level option claims it; see
      // the abbr survey in the PR adding this flag). If a future flag needs
      // `-v`, drop the `abbr:` here and keep `--version` only.
      ..addFlag(
        'version',
        abbr: 'v',
        defaultsTo: false,
        negatable: false,
        help: 'Print the fastlane_cli version and exit.',
      );

    addCommand(RunCommand());
    addCommand(ListCommand());
    addCommand(InitCommand());
    addCommand(DoctorCommand());
    addCommand(SkillsCommand());
    addCommand(CompletionCommand());
  }

  final FastlaneCliLauncher _launcher;
  final StringSink? _stdoutSink;

  /// Writes the version banner — separated for tests that prefer to assert
  /// against an injected sink rather than capture process stdout.
  void _writeVersion() {
    final sink = _stdoutSink;
    if (sink != null) {
      sink.write('fastlane_cli $fastlaneCliVersion\n');
    } else {
      stdout.write('fastlane_cli $fastlaneCliVersion\n');
    }
  }

  @override
  Future<int> run(Iterable<String> args) async {
    final argList = args.toList(growable: false);

    // `--version` / `-v` short-circuits everything: no profile, no
    // subcommand, no TUI. Scan the raw token list (rather than parsing
    // via argParser) so we never trip on missing required values of
    // *other* top-level options when the user only wanted the version.
    if (_wantsVersion(argList)) {
      _writeVersion();
      return 0;
    }

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

  /// Returns true if the user passed `--version` or `-v` at the top level
  /// (i.e. before any subcommand boundary). Stops scanning at `--` and at
  /// the first known subcommand name so `fastlane_cli run --version` is
  /// *not* hijacked here (a subcommand can still own its own `--version`
  /// if it ever wants to).
  bool _wantsVersion(List<String> args) {
    final subcommandNames = commands.keys.toSet();
    const valueFlags = <String>{'--profile', '-p', '--lang'};
    for (var i = 0; i < args.length; i++) {
      final token = args[i];
      if (token == '--') return false;
      if (token == '--version' || token == '-v') return true;
      if (!token.startsWith('-')) {
        // Hit a positional; if it's a subcommand, stop scanning so the
        // subcommand handles its own flags.
        if (subcommandNames.contains(token)) return false;
        // Otherwise keep scanning — TUI-style positional, not a subcommand.
        continue;
      }
      // Skip the value of a known `--opt value` pair.
      if (valueFlags.contains(token) && !token.contains('=')) {
        i++;
      }
    }
    return false;
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
      '-v',
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
          if (token == '--help' ||
              token == '-h' ||
              token == '--version' ||
              token == '-v') {
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
    ..addFlag('help', abbr: 'h', defaultsTo: false, negatable: false)
    ..addFlag('version', abbr: 'v', defaultsTo: false, negatable: false);
}
