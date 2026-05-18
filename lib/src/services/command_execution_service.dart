import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/command_request.dart';

/// Runs the child in a pseudo-TTY on Unix (`script(1)`) so tools like Fastlane
/// (Ruby `colored`) emit ANSI colors. `Process.start` pipes are not TTYs, so
/// without this, log output is uncolored.
///
/// [useUnixPty] is false in tests and other environments where `script` cannot
/// allocate a TTY (e.g. `dart test` capturing stdio).
({String executable, List<String> arguments, bool runInShell}) _spawnConfig(
  CommandRequest request, {
  required bool useUnixPty,
}) {
  if (Platform.isWindows) {
    return (
      executable: request.executable,
      arguments: request.arguments,
      runInShell: true,
    );
  }
  if (!useUnixPty) {
    return (
      executable: request.executable,
      arguments: request.arguments,
      runInShell: true,
    );
  }
  if (Platform.isMacOS) {
    return (
      executable: 'script',
      arguments: <String>[
        '-q',
        '/dev/null',
        request.executable,
        ...request.arguments,
      ],
      runInShell: false,
    );
  }
  final shellCmd = _joinUnixArgv(request.executable, request.arguments);
  return (
    executable: 'script',
    arguments: <String>['-q', '-c', shellCmd, '/dev/null'],
    runInShell: false,
  );
}

String _joinUnixArgv(String executable, List<String> arguments) {
  final parts = <String>[executable, ...arguments];
  return parts.map(_unixShellWord).join(' ');
}

String _unixShellWord(String arg) {
  if (arg.isEmpty) return "''";
  if (RegExp(r'^[a-zA-Z0-9.,/_:+=%@-]+$').hasMatch(arg)) return arg;
  return "'${arg.replaceAll("'", "'\\''")}'";
}

class CommandLogEvent {
  const CommandLogEvent({required this.message, required this.isError});

  final String message;
  final bool isError;
}

class CommandExecutionResult {
  const CommandExecutionResult({
    required this.exitCode,
    required this.wasDryRun,
  });

  final int exitCode;
  final bool wasDryRun;
}

abstract class CommandExecutionService {
  Future<CommandExecutionResult> run(
    CommandRequest request, {
    required bool dryRun,
    required void Function(CommandLogEvent event) onLog,
  });
}

class ProcessCommandExecutionService implements CommandExecutionService {
  const ProcessCommandExecutionService({this.useUnixPty = true});

  /// When true on macOS/Linux, wraps the command in `script(1)` so child
  /// processes see a TTY and emit ANSI colors (Fastlane, etc.).
  final bool useUnixPty;

  @override
  Future<CommandExecutionResult> run(
    CommandRequest request, {
    required bool dryRun,
    required void Function(CommandLogEvent event) onLog,
  }) async {
    if (dryRun) {
      onLog(
        CommandLogEvent(
          message: '[dry-run] ${request.displayCommand}',
          isError: false,
        ),
      );
      return const CommandExecutionResult(exitCode: 0, wasDryRun: true);
    }

    onLog(
      CommandLogEvent(
        message: '[exec] cwd=${request.workingDirectory}',
        isError: false,
      ),
    );
    onLog(
      CommandLogEvent(
        message:
            '[exec] BUNDLE_GEMFILE=${request.environment['BUNDLE_GEMFILE'] ?? '(unset)'}',
        isError: false,
      ),
    );

    final env = <String, String>{
      ...request.environment,
      if (!request.environment.containsKey('TERM')) 'TERM': 'xterm-256color',
    };

    final spawn = _spawnConfig(request, useUnixPty: useUnixPty);
    final Process process;
    try {
      process = await Process.start(
        spawn.executable,
        spawn.arguments,
        workingDirectory: request.workingDirectory,
        runInShell: spawn.runInShell,
        includeParentEnvironment: true,
        environment: env,
      );
    } on ProcessException catch (error) {
      onLog(
        CommandLogEvent(
          message:
              '[exec] spawn failed: ${error.message} (errorCode=${error.errorCode})',
          isError: true,
        ),
      );
      return const CommandExecutionResult(exitCode: -1, wasDryRun: false);
    }

    onLog(
      CommandLogEvent(message: '[exec] pid=${process.pid}', isError: false),
    );

    // Relay SIGINT (Ctrl+C) from the parent process to the spawned child so
    // that interrupting the CLI also interrupts the underlying `bundle exec
    // fastlane …` run. Without this, the child outlives the TUI on Ctrl+C
    // and orphan processes accumulate. We skip on Windows where Dart cannot
    // post signals to child processes.
    StreamSubscription<ProcessSignal>? sigintSub;
    if (!Platform.isWindows) {
      sigintSub = ProcessSignal.sigint.watch().listen((_) {
        try {
          process.kill(ProcessSignal.sigint);
        } catch (_) {
          // Child may have already exited — nothing to do.
        }
      });
    }

    unawaited(process.stdin.close());

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          onLog(CommandLogEvent(message: line, isError: false));
        })
        .asFuture<void>();

    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          onLog(CommandLogEvent(message: line, isError: true));
        })
        .asFuture<void>();

    final exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    await sigintSub?.cancel();
    return CommandExecutionResult(exitCode: exitCode, wasDryRun: false);
  }
}
