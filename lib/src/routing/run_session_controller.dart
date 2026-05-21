import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:nocterm/nocterm.dart' show ChangeNotifier;
import 'package:path/path.dart' as p;

import '../model/cli_action.dart';
import '../model/command_request.dart';
import '../model/run_session.dart';
import '../services/command_execution_service.dart';
import '../services/run_progress_parser.dart';
import '../services/run_prompt_parser.dart';
import '../util/ring_buffer.dart';
import 'environment.dart';

/// Maximum number of log entries retained per run session. Older entries are
/// dropped FIFO once the buffer is full. Same cap as the pre-v0.4.4 sliding
/// window, but now backed by a [RingBuffer] for O(1) append (was O(n) per
/// line via `List.sublist`).
const int kRunSessionLogCap = 300;

/// Maximum interval between an inbound log line and the resulting
/// `notifyListeners` call. 16 ms ≈ 60 Hz, the practical refresh ceiling
/// of a terminal; bursting 100+ lines/sec (xcodebuild, pod install) now
/// collapses to at most ~60 emits/sec instead of 100+.
const Duration kLogBatchInterval = Duration(milliseconds: 16);

/// Interval of the self-driving animation ticker. While a run is in an
/// active state ([RunStatus.validating] / [RunStatus.running]) this ticker
/// fires a bare `notifyListeners()` purely so the indeterminate spinner /
/// `ProgressBar` advances a frame and the log `ListView` repaints — even
/// during long SILENT child-process pauses (`flutter pub get`,
/// `xcodebuild` thinking) where zero log lines arrive and the v0.4.4 log
/// batch timer therefore never fires.
///
/// 80 ms ≈ 12.5 fps — smooth enough for a braille spinner without burning
/// CPU. The ticker only runs during an active run; an idle TUI (browsing
/// categories, no lane running) schedules zero wakeups.
const Duration kAnimationTickInterval = Duration(milliseconds: 80);

/// Run statuses considered "in progress". The animation ticker runs only
/// while the session is in one of these; reaching any other (terminal /
/// idle / awaiting-input) status stops it.
bool _isActiveRunStatus(RunStatus status) =>
    status == RunStatus.validating || status == RunStatus.running;

/// Per-tab run session state. Replaces the cubit's
/// `runSessionsByActionId` map. Each [RunRoute] owns one of these and disposes
/// it when its tab is closed.
class RunSessionController extends ChangeNotifier {
  RunSessionController({required this.actionId, required this.environment});

  final String actionId;
  final FastlaneCliEnvironment environment;

  /// Live ring buffer of every log entry observed since the most recent
  /// reset. The session's `logs` field is a snapshot of this buffer taken
  /// once per emit (so views observe a stable List during their build).
  final RingBuffer<RunLogEntry> _logRing =
      RingBuffer<RunLogEntry>(kRunSessionLogCap);

  RunSession _session = const RunSession(status: RunStatus.idle);
  RunSession get session => _session;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Pending log lines queued for the next batched emit. Drained by
  /// [_flushPendingLogs] on the trailing edge of the timer window.
  final Queue<RunLogEntry> _pendingLogs = Queue<RunLogEntry>();

  /// Carries forward the latest progress/prompt deltas observed while a
  /// batch was being assembled, so the eventual emit reflects them.
  RunProgressUpdate? _pendingProgress;
  RunPrompt? _pendingNewPrompt;

  /// Timer in flight for the next batched flush. Null when no batch is
  /// pending (the next [_appendLog] call schedules one).
  Timer? _batchTimer;

  /// Self-driving animation ticker. Non-null only while the run is in an
  /// active state (see [_isActiveRunStatus]). Drives spinner / progress-bar
  /// frames + log-list repaints during silent child-process pauses where no
  /// log lines arrive. Started by [_syncAnimationTicker] when the session
  /// enters an active status; cancelled when it leaves one and in [dispose].
  Timer? _animationTimer;

  /// Monotonically-increasing frame counter advanced once per animation
  /// tick. Views observe this (via [animationFrame]) to derive the spinner
  /// frame index, so the spinner advances off wall-clock time rather than
  /// off rebuild count — the latter stalls when the child is silent.
  int _animationFrame = 0;

  /// Current animation frame index. Increments every [kAnimationTickInterval]
  /// while a run is active. Stable (does not advance) while idle.
  int get animationFrame => _animationFrame;

  /// Test-only hook: every `_flushPendingLogs` invocation increments this.
  /// Lets unit tests assert that 1000 rapid appends collapse to ~16 emits.
  int debugFlushCount = 0;

  /// Test-only: true while the self-driving animation ticker is armed.
  bool get debugAnimationTickerActive => _animationTimer != null;

  /// Test-only: number of animation ticks fired so far. Mirrors
  /// [animationFrame] but named for regression-test clarity.
  int get debugAnimationTickCount => _animationFrame;

  /// The live child handle, set while a process is running. The prompt modal
  /// uses this to push the user's response back to the child's stdin.
  RunningProcess? _running;

  /// Test-only hook so unit tests can inject a fake [RunningProcess] without
  /// going through the executor. Production code never calls this.
  // ignore: use_setters_to_change_properties
  void debugAttachRunningProcess(RunningProcess process) {
    _running = process;
  }

  /// Flush any pending log batch synchronously. Useful in tests that need
  /// deterministic emit ordering without awaiting timer ticks.
  void debugFlushPendingLogs() {
    _flushPendingLogs();
  }

  void _emit(RunSession next) {
    _session = next;
    _syncAnimationTicker();
    notifyListeners();
  }

  /// Reset both the session AND the ring buffer. Used at the start of every
  /// run() so a retry sees a clean slate without carrying the previous run's
  /// trailing lines.
  void _resetState(RunSession next) {
    _logRing.clear();
    _pendingLogs.clear();
    _pendingProgress = null;
    _pendingNewPrompt = null;
    _batchTimer?.cancel();
    _batchTimer = null;
    _session = next;
    _syncAnimationTicker();
    notifyListeners();
  }

  /// Start or stop the self-driving animation ticker so it is armed exactly
  /// while the session is in an active status. Idempotent — safe to call on
  /// every `_emit` / `_resetState`. An idle controller (no run, or a run in
  /// a terminal state) holds no timer, so the TUI schedules zero wakeups
  /// while the user merely browses categories.
  void _syncAnimationTicker() {
    if (_isActiveRunStatus(_session.status)) {
      _startAnimationTicker();
    } else {
      _stopAnimationTicker();
    }
  }

  void _startAnimationTicker() {
    if (_animationTimer != null) return;
    _animationTimer = Timer.periodic(kAnimationTickInterval, _onAnimationTick);
  }

  void _stopAnimationTicker() {
    _animationTimer?.cancel();
    _animationTimer = null;
  }

  /// Animation tick: advance the frame counter and notify listeners purely
  /// to repaint. This fires even when ZERO log lines have arrived — that is
  /// the whole point: it un-freezes the spinner + log list during silent
  /// lane steps. It deliberately does NOT touch [_session]; nocterm dedupes
  /// this `notifyListeners` with any coincident log-batch flush within the
  /// same frame, so the two timers never fight.
  void _onAnimationTick(Timer _) {
    // Defensive: if the run somehow left an active state without the ticker
    // being torn down, stop here rather than spinning forever.
    if (!_isActiveRunStatus(_session.status)) {
      _stopAnimationTicker();
      return;
    }
    _animationFrame++;
    notifyListeners();
  }

  Future<RunSession> run({bool confirmed = false}) async {
    if (_isRunning) return _session;

    final action = environment.profile.actionsById[actionId];
    if (action == null) {
      _resetState(
        RunSession(
          status: RunStatus.failed,
          actionId: actionId,
          logs: <RunLogEntry>[
            RunLogEntry(message: 'Action not found.', isError: true),
          ],
        ),
      );
      return _session;
    }

    if (action.requiresConfirmation && !confirmed) {
      _resetState(
        RunSession(
          status: RunStatus.confirmationRequired,
          actionId: action.id,
          logs: <RunLogEntry>[
            RunLogEntry(
              message: 'Confirmation required for ${action.id}.',
              isError: false,
            ),
          ],
        ),
      );
      return _session;
    }

    final overwriteTargets = _overwriteTargets(action);
    if (action.requiresOverwriteConfirmation &&
        overwriteTargets.isNotEmpty &&
        !confirmed) {
      _resetState(
        RunSession(
          status: RunStatus.confirmationRequired,
          actionId: action.id,
          logs: <RunLogEntry>[
            RunLogEntry(
              message:
                  'Overwrite confirmation required: existing destination content detected.',
              isError: false,
            ),
            ...overwriteTargets.map(
              (path) => RunLogEntry(message: path, isError: false),
            ),
          ],
        ),
      );
      return _session;
    }

    _isRunning = true;
    _resetState(
      RunSession(
        status: RunStatus.validating,
        actionId: action.id,
        progressIndeterminate: true,
        logs: const <RunLogEntry>[],
      ),
    );

    final preflight = environment.preflightValidator.validate(
      profile: environment.profile,
      action: action,
    );
    if (!preflight.success) {
      final entries = <RunLogEntry>[
        RunLogEntry(
          message: 'Action blocked by preflight validation.',
          isError: true,
        ),
        ...preflight.errors.map(
          (item) => RunLogEntry(message: item, isError: true),
        ),
      ];
      _logRing.addAll(entries);
      _emit(
        RunSession(
          status: RunStatus.blocked,
          actionId: action.id,
          guideTopic: preflight.guideTopic,
          validationErrors: preflight.errors,
          validationChecklist: preflight.checklist,
          logs: _logRing.toListSnapshot(),
        ),
      );
      _isRunning = false;
      return _session;
    }

    late final CommandRequest request;
    try {
      request = environment.commandBuilder.build(
        profile: environment.profile,
        action: action,
      );
    } catch (error) {
      _logRing.add(
        RunLogEntry(message: 'Command build failed: $error', isError: true),
      );
      _emit(
        RunSession(
          status: RunStatus.failed,
          actionId: action.id,
          progressIndeterminate: false,
          progressValue: 1,
          validationChecklist: preflight.checklist,
          logs: _logRing.toListSnapshot(),
        ),
      );
      _isRunning = false;
      return _session;
    }

    _logRing.add(
      RunLogEntry(message: request.displayCommand, isError: false),
    );
    _emit(
      RunSession(
        status: RunStatus.running,
        actionId: action.id,
        command: request.displayCommand,
        progressIndeterminate: true,
        validationChecklist: preflight.checklist,
        logs: _logRing.toListSnapshot(),
      ),
    );

    late final CommandExecutionResult result;
    try {
      result = await environment.executionService.run(
        request,
        dryRun: environment.dryRun,
        onLog: (event) => _appendLog(event.message, isError: event.isError),
        onProcess: (process) {
          _running = process;
        },
      );
    } catch (error) {
      // Drain any in-flight batch BEFORE the failure marker so log order is
      // preserved (otherwise the error could appear ahead of trailing
      // streamed output captured just before the throw).
      _flushPendingLogs();
      _logRing.add(
        RunLogEntry(
          message: 'Command execution failed: $error',
          isError: true,
        ),
      );
      _emit(
        _session.copyWith(
          status: RunStatus.failed,
          exitCode: -1,
          progressIndeterminate: false,
          progressValue: 1,
          logs: _logRing.toListSnapshot(),
        ),
      );
      _isRunning = false;
      _running = null;
      return _session;
    }

    final finalStatus = result.wasDryRun
        ? RunStatus.dryRun
        : result.exitCode == 0
        ? RunStatus.succeeded
        : RunStatus.failed;

    _flushPendingLogs();
    _logRing.add(
      RunLogEntry(
        message: 'Exit code: ${result.exitCode}',
        isError: result.exitCode != 0,
      ),
    );
    _emit(
      _session.copyWith(
        status: finalStatus,
        exitCode: result.exitCode,
        progressIndeterminate: false,
        progressValue: 1,
        logs: _logRing.toListSnapshot(),
      ),
    );
    _isRunning = false;
    _running = null;
    return _session;
  }

  /// Streaming log entry handler. Enqueues into the pending buffer and
  /// schedules a flush on the next 16 ms boundary. The flush coalesces every
  /// line that arrived in the window into ONE `notifyListeners()` call.
  ///
  /// This is the hot path: a verbose `xcodebuild` lane fires 100+ lines per
  /// second. Before v0.4.4 each one rebuilt the entire session + copied the
  /// log list (O(n)); now they all share a single ring-buffer push + a
  /// debounced emit.
  void _appendLog(String line, {required bool isError}) {
    final entry = RunLogEntry(message: line, isError: isError);
    _pendingLogs.add(entry);

    // Parse progress / prompt eagerly so the next flush has the most recent
    // signal. Prompt parsing is gated the same way as before: only look for
    // a prompt while none is already pending (Fastlane echoes prompts on
    // retry and overwriting `activePrompt` mid-modal would clobber typing).
    final progressUpdate = environment.progressParser.parse(line);
    if (progressUpdate != null) {
      _pendingProgress = progressUpdate;
    }
    if (_session.activePrompt == null && _pendingNewPrompt == null) {
      final newPrompt = environment.promptParser.parse(line);
      if (newPrompt != null) {
        _pendingNewPrompt = newPrompt;
      }
    }

    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_batchTimer != null) return;
    _batchTimer = Timer(kLogBatchInterval, _flushPendingLogs);
  }

  void _flushPendingLogs() {
    _batchTimer?.cancel();
    _batchTimer = null;
    debugFlushCount++;
    if (_pendingLogs.isEmpty &&
        _pendingProgress == null &&
        _pendingNewPrompt == null) {
      return;
    }

    // Drain pending lines into the ring buffer. The ring takes care of
    // dropping oldest entries when at capacity.
    while (_pendingLogs.isNotEmpty) {
      _logRing.add(_pendingLogs.removeFirst());
    }

    final progressUpdate = _pendingProgress;
    final newPrompt = _pendingNewPrompt;
    _pendingProgress = null;
    _pendingNewPrompt = null;

    _emit(
      _session.copyWith(
        logs: _logRing.toListSnapshot(),
        activeFile: progressUpdate?.activeFile,
        progressIndeterminate:
            progressUpdate?.indeterminate ?? _session.progressIndeterminate,
        progressValue:
            progressUpdate?.progressValue ?? _session.progressValue,
        activePrompt: newPrompt ?? _session.activePrompt,
      ),
    );
  }

  /// Submit the user's response to the currently-active prompt. Runs the
  /// validator; if it returns an error, the modal stays open with the error
  /// message attached. On valid input, writes the line to the child's stdin
  /// and clears [RunSession.activePrompt].
  ///
  /// Returns the validator error (or null on success) so callers (the modal)
  /// can show it inline before the dialog re-renders.
  Future<String?> submitPromptResponse(String value) async {
    final prompt = _session.activePrompt;
    if (prompt == null) return null;
    final error = prompt.validator(value);
    if (error != null) {
      _emit(_session.copyWith(activePrompt: prompt.withValidationError(error)));
      return error;
    }
    final wrote = await _running?.writeStdin(value) ?? false;
    _logRing.add(
      RunLogEntry(
        message: wrote
            ? '[prompt] response sent'
            : '[prompt] response NOT sent (no live process)',
        isError: !wrote,
      ),
    );
    _emit(
      _session.copyWith(
        activePrompt: null,
        respondedAt: DateTime.now(),
        logs: _logRing.toListSnapshot(),
      ),
    );
    return null;
  }

  /// Drop the active prompt without responding. By default this also relays
  /// SIGINT to the child — dismissing an open prompt implies "stop this
  /// lane". Set [sigint] to false to clear the dialog without aborting the
  /// run (used by tests).
  void dismissPrompt({bool sigint = true}) {
    if (_session.activePrompt == null) return;
    if (sigint) {
      _running?.signal(ProcessSignal.sigint);
    }
    _emit(_session.copyWith(activePrompt: null));
  }

  @override
  void dispose() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _stopAnimationTicker();
    _pendingLogs.clear();
    super.dispose();
  }

  List<String> _overwriteTargets(CliAction action) {
    final options = action.command.options;
    final raw = <String>[
      if (options.containsKey('metadata_path')) options['metadata_path'] ?? '',
      if (options.containsKey('screenshots_path'))
        options['screenshots_path'] ?? '',
    ].where((s) => s.trim().isNotEmpty).toSet();

    final resolved = <String>[];
    for (final r in raw) {
      final normalized = p.normalize(
        p.isAbsolute(r) ? r : p.join(environment.profile.appRootPath, r),
      );
      final dir = Directory(normalized);
      if (!dir.existsSync()) continue;
      if (dir.listSync().isEmpty) continue;
      resolved.add(normalized);
    }
    return resolved;
  }
}
