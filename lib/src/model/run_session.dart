import 'package:nocterm/nocterm.dart' show InlineSpan, TextStyle;

import '../services/run_prompt_parser.dart';
import '../ui/ansi_parsed_log_line.dart';

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

/// One emitted log line. Immutable from the caller's perspective; the
/// [_parsedAnsiCache] field is a private memoisation slot used by the view
/// layer to avoid re-running the ANSI parser on every rebuild (see W9 perf
/// fix in v0.4.4). Reading [parsedAnsi] with the same [baseStyle] twice
/// returns the cached span; passing a different style invalidates the cache
/// and re-parses.
class RunLogEntry {
  RunLogEntry({required this.message, required this.isError});

  final String message;
  final bool isError;

  /// Lazily-populated parse result. Mutable purely as a cache; the entry's
  /// observable identity ([message], [isError]) is still effectively
  /// immutable.
  InlineSpan? _parsedAnsiCache;
  TextStyle? _cachedBaseStyle;

  /// Test hook — how many times the underlying parser has been invoked for
  /// this entry. Useful to assert that the cache short-circuits repeated
  /// renders. Only incremented inside [parsedAnsi].
  int debugParseCount = 0;

  /// Cached ANSI parse of [message] with [baseStyle]. Subsequent calls with
  /// the same [baseStyle] return the cached span without re-running the
  /// regex/SGR machinery; a different [baseStyle] invalidates the cache.
  ///
  /// Note: const-constructed entries (via [RunLogEntry.constant]) cannot
  /// cache (the backing fields are final). Those entries always re-parse,
  /// which is fine because they are rendered at most once each.
  InlineSpan parsedAnsi({required TextStyle baseStyle}) {
    final cached = _parsedAnsiCache;
    if (cached != null && _cachedBaseStyle == baseStyle) {
      return cached;
    }
    debugParseCount++;
    final span = ansiLineToSpan(message, baseStyle: baseStyle);
    _parsedAnsiCache = span;
    _cachedBaseStyle = baseStyle;
    return span;
  }
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

  /// Captured log lines in chronological order. Backed in production by a
  /// snapshot of the controller's `RingBuffer<RunLogEntry>` (see
  /// [RunSessionController] — the controller takes a snapshot on every emit
  /// so views observe a stable, indexable list during their build).
  ///
  /// Per the v0.4.4 perf fix: the controller batches appends and only takes
  /// one snapshot per batched notify — so this is no longer the hot O(n)
  /// path it used to be (was: per-line `List.sublist` copy).
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
