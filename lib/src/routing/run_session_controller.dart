import 'dart:async';
import 'dart:io';

import 'package:nocterm/nocterm.dart' show ChangeNotifier;
import 'package:path/path.dart' as p;

import '../model/cli_action.dart';
import '../model/command_request.dart';
import '../model/run_session.dart';
import '../services/command_execution_service.dart';
import '../services/run_prompt_parser.dart';
import 'environment.dart';

/// Per-tab run session state. Replaces the cubit's
/// `runSessionsByActionId` map. Each [RunRoute] owns one of these and disposes
/// it when its tab is closed.
class RunSessionController extends ChangeNotifier {
  RunSessionController({required this.actionId, required this.environment});

  final String actionId;
  final FastlaneCliEnvironment environment;

  RunSession _session = const RunSession(status: RunStatus.idle);
  RunSession get session => _session;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// The live child handle, set while a process is running. The prompt modal
  /// uses this to push the user's response back to the child's stdin.
  RunningProcess? _running;

  /// Test-only hook so unit tests can inject a fake [RunningProcess] without
  /// going through the executor. Production code never calls this.
  // ignore: use_setters_to_change_properties
  void debugAttachRunningProcess(RunningProcess process) {
    _running = process;
  }

  void _emit(RunSession next) {
    _session = next;
    notifyListeners();
  }

  Future<RunSession> run({bool confirmed = false}) async {
    if (_isRunning) return _session;

    final action = environment.profile.actionsById[actionId];
    if (action == null) {
      _emit(
        RunSession(
          status: RunStatus.failed,
          actionId: actionId,
          logs: const [
            RunLogEntry(message: 'Action not found.', isError: true),
          ],
        ),
      );
      return _session;
    }

    if (action.requiresConfirmation && !confirmed) {
      _emit(
        RunSession(
          status: RunStatus.confirmationRequired,
          actionId: action.id,
          logs: [
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
      _emit(
        RunSession(
          status: RunStatus.confirmationRequired,
          actionId: action.id,
          logs: [
            const RunLogEntry(
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
    _emit(
      RunSession(
        status: RunStatus.validating,
        actionId: action.id,
        progressIndeterminate: true,
        logs: const [],
      ),
    );

    final preflight = environment.preflightValidator.validate(
      profile: environment.profile,
      action: action,
    );
    if (!preflight.success) {
      _emit(
        RunSession(
          status: RunStatus.blocked,
          actionId: action.id,
          guideTopic: preflight.guideTopic,
          validationErrors: preflight.errors,
          validationChecklist: preflight.checklist,
          logs: [
            const RunLogEntry(
              message: 'Action blocked by preflight validation.',
              isError: true,
            ),
            ...preflight.errors.map(
              (item) => RunLogEntry(message: item, isError: true),
            ),
          ],
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
      _emit(
        RunSession(
          status: RunStatus.failed,
          actionId: action.id,
          progressIndeterminate: false,
          progressValue: 1,
          validationChecklist: preflight.checklist,
          logs: [
            RunLogEntry(message: 'Command build failed: $error', isError: true),
          ],
        ),
      );
      _isRunning = false;
      return _session;
    }

    _emit(
      RunSession(
        status: RunStatus.running,
        actionId: action.id,
        command: request.displayCommand,
        progressIndeterminate: true,
        validationChecklist: preflight.checklist,
        logs: [RunLogEntry(message: request.displayCommand, isError: false)],
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
      _emit(
        _session.copyWith(
          status: RunStatus.failed,
          exitCode: -1,
          progressIndeterminate: false,
          progressValue: 1,
          logs: _bounded([
            ..._session.logs,
            RunLogEntry(
              message: 'Command execution failed: $error',
              isError: true,
            ),
          ]),
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

    _emit(
      _session.copyWith(
        status: finalStatus,
        exitCode: result.exitCode,
        progressIndeterminate: false,
        progressValue: 1,
        logs: _bounded([
          ..._session.logs,
          RunLogEntry(
            message: 'Exit code: ${result.exitCode}',
            isError: result.exitCode != 0,
          ),
        ]),
      ),
    );
    _isRunning = false;
    _running = null;
    return _session;
  }

  void _appendLog(String line, {required bool isError}) {
    final progressUpdate = environment.progressParser.parse(line);

    // Only look for a prompt when one isn't already pending. Fastlane often
    // echoes the same prompt twice (once on first print, once on retry), and
    // overwriting `activePrompt` mid-modal would reset the user's typing.
    final RunPrompt? newPrompt =
        _session.activePrompt == null ? environment.promptParser.parse(line) : null;

    _emit(
      _session.copyWith(
        logs: _bounded([
          ..._session.logs,
          RunLogEntry(message: line, isError: isError),
        ]),
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
    _emit(
      _session.copyWith(
        activePrompt: null,
        respondedAt: DateTime.now(),
        logs: _bounded([
          ..._session.logs,
          RunLogEntry(
            message: wrote
                ? '[prompt] response sent'
                : '[prompt] response NOT sent (no live process)',
            isError: !wrote,
          ),
        ]),
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

  static List<RunLogEntry> _bounded(List<RunLogEntry> logs) {
    const max = 300;
    if (logs.length <= max) return logs;
    return logs.sublist(logs.length - max);
  }
}
