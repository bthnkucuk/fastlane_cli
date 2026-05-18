import 'dart:async';
import 'dart:io';

import 'package:fastlane_cli/src/cli/fastlane_cli_runner.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart';

/// Entry point.
///
/// Wraps the runner in [runZonedGuarded] so an uncaught Dart exception from
/// any async edge — TUI render loop, signal handler, stream listener — still
/// triggers a [ProcessSupervisor.shutdownAll] before the process exits.
/// Without this guard, a panic in the parent would abandon the spawned
/// `bundle exec fastlane …` child and orphan it.
Future<void> main(List<String> arguments) async {
  // Touch the supervisor early so its signal listeners (SIGINT/SIGTERM/SIGHUP
  // on POSIX) are installed BEFORE the first lane spawn. Without this, a
  // signal received during bundle bootstrap (before any Process.start)
  // would have nothing listening and Dart's default disposition (terminate)
  // would still orphan in-flight children spawned by other tabs.
  ProcessSupervisor.instance;

  await runZonedGuarded<Future<void>>(() async {
    final code = await FastlaneCliRunner().run(arguments);
    if (code != 0) {
      exitCode = code;
    }
  }, (error, stack) async {
    // Best-effort teardown of every supervised child before reporting + exit.
    try {
      await ProcessSupervisor.instance.shutdownAll();
    } catch (_) {
      // Swallow — we're already on the panic path; nothing useful to do.
    }
    stderr.writeln('Unhandled exception: $error');
    stderr.writeln(stack);
    exitCode = 1;
  });
}
