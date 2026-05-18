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
    );
  }
}
