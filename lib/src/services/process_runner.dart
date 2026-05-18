import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result of a one-shot, output-captured process invocation. Mirrors the shape
/// of [ProcessResult] but as a plain data class so tests can construct it
/// without spawning anything.
class ProcessRunResult {
  const ProcessRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Convenience: trimmed first non-empty line of stdout (or empty string).
  String get firstStdoutLine {
    for (final line in const LineSplitter().convert(stdout)) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }
}

/// Thrown when the OS cannot find the executable (errno ENOENT). Distinct
/// from a non-zero exit so [DoctorService] can phrase remediation correctly.
class ProcessNotFoundException implements Exception {
  const ProcessNotFoundException(this.executable, this.cause);

  final String executable;
  final Object cause;

  @override
  String toString() => 'Executable not found: $executable ($cause)';
}

/// Small abstraction over [Process.run] / [Process.start] so unit tests can
/// inject canned outputs. Production code uses [SystemProcessRunner]; tests
/// pass a fake. Intentionally narrow — only the verbs `DoctorService`
/// actually needs.
abstract class ProcessRunner {
  /// Capture-mode run: collects stdout/stderr fully before returning.
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  /// Streaming run: stdout/stderr are forwarded line-by-line to [onLog] as
  /// they arrive. Useful for `bundle install`, where the install can take a
  /// while and silence would feel like a hang.
  Future<int> runStreaming(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required void Function(String line, {required bool isError}) onLog,
  });
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return ProcessRunResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } on ProcessException catch (error) {
      throw ProcessNotFoundException(executable, error);
    }
  }

  @override
  Future<int> runStreaming(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required void Function(String line, {required bool isError}) onLog,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: false,
        includeParentEnvironment: true,
      );
    } on ProcessException catch (error) {
      throw ProcessNotFoundException(executable, error);
    }

    unawaited(process.stdin.close());

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog(line, isError: false))
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog(line, isError: true))
        .asFuture<void>();

    final exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    return exitCode;
  }
}
