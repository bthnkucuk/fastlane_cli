import '../services/run_prompt_parser.dart';

enum RunStatus {
  idle,
  validating,
  blocked,
  confirmationRequired,
  running,
  succeeded,
  failed,
  dryRun,
}

class RunLogEntry {
  const RunLogEntry({required this.message, required this.isError});

  final String message;
  final bool isError;
}

/// Sentinel used by [RunSession.copyWith] so callers can distinguish "leave
/// this field untouched" (default) from "explicitly clear this field"
/// (`activePrompt: null`). Dart's default-parameter machinery cannot tell
/// those apart through a typed `RunPrompt?`, so we use `Object?` parameters
/// plus this private marker — same pattern Flutter uses internally on
/// `copyWith`-like APIs.
class _NoChange {
  const _NoChange();
}

const Object _kNoChange = _NoChange();

class RunSession {
  const RunSession({
    required this.status,
    this.actionId,
    this.command,
    this.exitCode,
    this.guideTopic,
    this.progressValue,
    this.progressIndeterminate = true,
    this.activeFile,
    this.validationErrors = const <String>[],
    this.validationChecklist = const <String>[],
    this.logs = const <RunLogEntry>[],
    this.activePrompt,
    this.respondedAt,
  });

  factory RunSession.initial() => const RunSession(status: RunStatus.idle);

  final RunStatus status;
  final String? actionId;
  final String? command;
  final int? exitCode;
  final String? guideTopic;
  final double? progressValue;
  final bool progressIndeterminate;
  final String? activeFile;
  final List<String> validationErrors;
  final List<String> validationChecklist;
  final List<RunLogEntry> logs;

  /// Unanswered interactive prompt the spawned child is waiting on. Null
  /// when nothing is blocking. Cleared via `copyWith(activePrompt: null)`
  /// (the sentinel pattern below makes that distinguishable from "leave it
  /// alone").
  final RunPrompt? activePrompt;

  /// Wall-clock timestamp of the most recent prompt response. Useful for
  /// analytics / debug: "how long did the user spend on the 2FA modal?". Not
  /// rendered in the UI directly.
  final DateTime? respondedAt;

  RunSession copyWith({
    RunStatus? status,
    String? actionId,
    String? command,
    int? exitCode,
    String? guideTopic,
    double? progressValue,
    bool? progressIndeterminate,
    String? activeFile,
    List<String>? validationErrors,
    List<String>? validationChecklist,
    List<RunLogEntry>? logs,
    Object? activePrompt = _kNoChange,
    Object? respondedAt = _kNoChange,
  }) {
    return RunSession(
      status: status ?? this.status,
      actionId: actionId ?? this.actionId,
      command: command ?? this.command,
      exitCode: exitCode ?? this.exitCode,
      guideTopic: guideTopic ?? this.guideTopic,
      progressValue: progressValue ?? this.progressValue,
      progressIndeterminate:
          progressIndeterminate ?? this.progressIndeterminate,
      activeFile: activeFile ?? this.activeFile,
      validationErrors: validationErrors ?? this.validationErrors,
      validationChecklist: validationChecklist ?? this.validationChecklist,
      logs: logs ?? this.logs,
      activePrompt: identical(activePrompt, _kNoChange)
          ? this.activePrompt
          : activePrompt as RunPrompt?,
      respondedAt: identical(respondedAt, _kNoChange)
          ? this.respondedAt
          : respondedAt as DateTime?,
    );
  }
}
