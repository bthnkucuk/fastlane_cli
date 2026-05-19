import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../model/command_request.dart';
import 'doctor_service.dart';

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

/// Patterns (case-insensitive substrings of the env-key name) whose values
/// must be redacted in any logged output. Mirrors the Ruby-side
/// `SUMMARY_BOX_SECRET_KEY_PATTERNS` in `fastlane/common_helpers.rb` so the
/// Dart-side dry-run logger does not leak secrets when the user has loaded
/// credentials via `fastlane/.env`.
const List<String> _secretKeyPatterns = <String>[
  'password',
  'api_key',
  'api-key',
  'secret',
  'token',
  'private_key',
  'json_key_data',
  'client_secret',
  'authorization',
  'auth',
];

String _redactEnvValue(String key, String value) {
  if (value.isEmpty) return value;
  final lowerKey = key.toLowerCase();
  for (final pattern in _secretKeyPatterns) {
    if (lowerKey.contains(pattern)) {
      return '***';
    }
  }
  return value;
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

/// Process-lifecycle supervisor.
///
/// Owns a registry of every live child [Process] spawned by
/// [ProcessCommandExecutionService] and a single set of OS-signal listeners
/// (SIGINT / SIGTERM / SIGHUP on POSIX) that relay the received signal to
/// every registered child. Also exposes [shutdownAll] for graceful + forceful
/// teardown from non-signal paths (in-app quit, unhandled exception, etc.).
///
/// Why this exists: without it, when the TUI quits while a `bundle exec
/// fastlane …` lane is mid-flight, the spawned Ruby child outlives the parent
/// and accumulates as an orphan. This was partially patched for Ctrl+C in
/// 63b8e4e, but every other exit path (Q-quit, SIGTERM, SIGHUP, uncaught
/// Dart exception) still leaked. [ProcessSupervisor] closes those gaps in one
/// place.
///
/// Signal handling on Windows is unreliable (Dart cannot post POSIX signals
/// to children). On Windows, registry teardown falls back to `Process.kill`
/// without a specific signal, which becomes a forceful terminate.
class ProcessSupervisor {
  ProcessSupervisor._();

  static final ProcessSupervisor instance = ProcessSupervisor._();

  final Set<Process> _live = <Process>{};
  bool _signalsInstalled = false;
  final List<StreamSubscription<ProcessSignal>> _signalSubs =
      <StreamSubscription<ProcessSignal>>[];

  /// Number of children currently being supervised. Test-only hook.
  int get liveCount => _live.length;

  /// Register a freshly-spawned [Process]. Idempotent — registering the same
  /// process twice is a no-op.
  void register(Process process) {
    _live.add(process);
    _ensureSignalsInstalled();
    // Auto-deregister when the child exits on its own.
    // ignore: unawaited_futures
    process.exitCode.whenComplete(() {
      _live.remove(process);
    });
  }

  /// Unregister a [Process] (used by tests and by the executor on normal
  /// completion paths).
  void unregister(Process process) {
    _live.remove(process);
  }

  /// Install SIGINT/SIGTERM/SIGHUP listeners exactly once. Each listener
  /// relays the received signal to every registered child. We do NOT call
  /// [exit] from the handler — the parent's normal exit path (nocterm
  /// `shutdownApp` or `runZonedGuarded` error handler) is responsible for
  /// terminating the TUI itself. Our only job is to make sure children die.
  void _ensureSignalsInstalled() {
    if (_signalsInstalled) return;
    if (Platform.isWindows) {
      // ProcessSignal.watch is unsupported / unreliable on Windows. Skip.
      _signalsInstalled = true;
      return;
    }
    _signalsInstalled = true;
    void install(ProcessSignal signal) {
      try {
        _signalSubs.add(signal.watch().listen((_) {
          _relayToAll(signal);
        }));
      } on SignalException {
        // Some signals (e.g. SIGHUP under Dart test isolates) cannot be
        // watched in every environment. Silently skip.
      }
    }
    install(ProcessSignal.sigint);
    install(ProcessSignal.sigterm);
    install(ProcessSignal.sighup);
  }

  void _relayToAll(ProcessSignal signal) {
    // Snapshot the set so concurrent modification during iteration is safe.
    final snapshot = _live.toList(growable: false);
    for (final process in snapshot) {
      try {
        process.kill(signal);
      } catch (_) {
        // Child may have already exited — nothing to do.
      }
    }
  }

  /// Tear down every live child. First sends [signal] (default SIGINT) and
  /// waits up to [graceful] for each child to exit; any survivor is then
  /// sent SIGKILL.
  ///
  /// Safe to call repeatedly. Returns once every supervised child has either
  /// exited or been SIGKILL'd. Callers (e.g. the in-app quit handler) should
  /// await this BEFORE invoking `shutdownApp()` to avoid orphans.
  Future<void> shutdownAll({
    Duration graceful = const Duration(milliseconds: 500),
    ProcessSignal signal = ProcessSignal.sigint,
  }) async {
    if (_live.isEmpty) return;
    final snapshot = _live.toList(growable: false);

    // Phase 1: graceful kill.
    for (final process in snapshot) {
      try {
        if (Platform.isWindows) {
          process.kill();
        } else {
          process.kill(signal);
        }
      } catch (_) {
        // already gone
      }
    }

    // Phase 2: await exit with timeout.
    final waits = <Future<int?>>[
      for (final process in snapshot)
        process.exitCode
            .then<int?>((c) => c)
            .timeout(graceful, onTimeout: () => null),
    ];
    final results = await Future.wait(waits);

    // Phase 3: SIGKILL any straggler.
    for (var i = 0; i < snapshot.length; i++) {
      if (results[i] != null) continue;
      try {
        snapshot[i].kill(ProcessSignal.sigkill);
      } catch (_) {
        // already gone
      }
    }
  }

  /// Drop every signal listener. Test-only hook so isolates don't leak
  /// listeners across test cases.
  Future<void> resetForTesting() async {
    for (final sub in _signalSubs) {
      await sub.cancel();
    }
    _signalSubs.clear();
    _signalsInstalled = false;
    _live.clear();
  }
}

class ProcessCommandExecutionService implements CommandExecutionService {
  ProcessCommandExecutionService({
    this.useUnixPty = true,
    DoctorService? doctorService,
    ProcessSupervisor? supervisor,
  })  : _doctorService = doctorService ?? DoctorService(),
        _supervisor = supervisor ?? ProcessSupervisor.instance;

  /// When true on macOS/Linux, wraps the command in `script(1)` so child
  /// processes see a TTY and emit ANSI colors (Fastlane, etc.).
  final bool useUnixPty;

  /// Lazily bootstraps the user-cache bundle the first time a fastlane lane
  /// runs. Injected so tests can supply a no-op.
  final DoctorService _doctorService;

  /// Tracks every live child so we can tear them all down on any exit path
  /// (Ctrl+C, in-app Q, SIGTERM, SIGHUP, uncaught exception).
  final ProcessSupervisor _supervisor;

  @override
  Future<CommandExecutionResult> run(
    CommandRequest request, {
    required bool dryRun,
    required void Function(CommandLogEvent event) onLog,
  }) async {
    if (dryRun) {
      onLog(
        CommandLogEvent(
          message: '[dry-run] cwd=${request.workingDirectory}',
          isError: false,
        ),
      );
      if (request.environment.isNotEmpty) {
        onLog(
          CommandLogEvent(
            message: '[dry-run] env (${request.environment.length} keys):',
            isError: false,
          ),
        );
        final keys = request.environment.keys.toList()..sort();
        for (final key in keys) {
          final value = request.environment[key] ?? '';
          final shown = _redactEnvValue(key, value);
          onLog(
            CommandLogEvent(
              message: '[dry-run]   $key=$shown',
              isError: false,
            ),
          );
        }
      }
      onLog(
        CommandLogEvent(
          message: '[dry-run] ${request.displayCommand}',
          isError: false,
        ),
      );
      return const CommandExecutionResult(exitCode: 0, wasDryRun: true);
    }

    // Bootstrap the per-user bundle cache the first time a `bundle exec …`
    // process (currently used only by storepilot_bridge.rb) runs in this
    // process. Fastlane lanes do NOT go through `bundle` anymore — they
    // invoke the system / brew-installed `fastlane` gem directly (see
    // CommandBuilder._buildFastlane and CLAUDE.md §4). Subsequent calls are
    // a no-op (DoctorService memoizes the result), so this is safe to call
    // on every invocation. We stream notice/install output through stderr
    // so the user sees progress rather than a silent hang.
    if (request.executable == 'bundle') {
      try {
        await _doctorService.ensureBundleReady(
          noticeSink: _BundleNoticeSink(onLog),
        );
      } catch (error) {
        onLog(
          CommandLogEvent(
            message: '[exec] bundle bootstrap failed: $error',
            isError: true,
          ),
        );
      }
    }

    onLog(
      CommandLogEvent(
        message: '[exec] cwd=${request.workingDirectory}',
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
      // mode defaults to ProcessStartMode.normal: child shares stdin/stdout
      // with the parent process group on POSIX. We must NOT pass
      // ProcessStartMode.detached or detachedWithStdio here — those would
      // start the child in its own session and survive the parent on Mac
      // and Linux. Even though `script(1)` is involved on POSIX, it does
      // not setsid by default, so the child stays in our process group.
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

    // Register with the supervisor BEFORE we start awaiting exit, so the
    // signal listeners installed in `register()` are in place ahead of any
    // possible SIGINT / SIGTERM / SIGHUP that arrives during the child's
    // lifetime. The supervisor relays POSIX signals received by the parent
    // to the child and provides the explicit shutdownAll() entry point used
    // by the in-app quit handler.
    _supervisor.register(process);

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
    _supervisor.unregister(process);
    return CommandExecutionResult(exitCode: exitCode, wasDryRun: false);
  }
}

/// Adapts a `CommandLogEvent` callback into a [StringSink] so [DoctorService]
/// can emit its first-run bundle-install output through the same channel as
/// every other line the executor produces.
class _BundleNoticeSink implements StringSink {
  _BundleNoticeSink(this._onLog);

  final void Function(CommandLogEvent event) _onLog;
  final StringBuffer _buffer = StringBuffer();

  void _flushLine(String line) {
    if (line.isEmpty) return;
    _onLog(CommandLogEvent(message: line, isError: true));
  }

  @override
  void write(Object? obj) {
    _buffer.write(obj);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _buffer.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    _buffer.writeCharCode(charCode);
  }

  @override
  void writeln([Object? obj = '']) {
    _buffer.write(obj);
    _flushLine(_buffer.toString());
    _buffer.clear();
  }
}
