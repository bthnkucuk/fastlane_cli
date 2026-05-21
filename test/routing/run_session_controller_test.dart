import 'dart:async';
import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart';
import 'package:fastlane_cli/src/services/guide_registry.dart';
import 'package:test/test.dart';

import '../support/profile_factory.dart';

FastlaneCliEnvironment _buildEnvironment(
  CommandExecutionService executor, {
  required String appRootPath,
}) {
  final profile = createTestProfile(
    appRootPath: appRootPath,
    categories: <CliCategory>[
      makeCategory(id: 'general', actionIds: <String>['noop']),
    ],
    actions: <CliAction>[
      makeFastlaneAction(id: 'noop', categoryId: 'general', lane: 'noop'),
    ],
  );
  return FastlaneCliEnvironment(
    profile: profile,
    initialLocale: AppLocale.en,
    dryRun: true,
    commandBuilder: const CommandBuilder(),
    executionService: executor,
    preflightValidator: const PreflightValidator(),
    guideRegistry: const GuideRegistry(),
  );
}

Directory _ensureTempRunner() {
  // CommandBuilder._buildFastlane requires the runner working directory
  // (= dirname(profile.fastlaneRunnerDirectoryPath)) to exist on disk.
  // We use a fresh temp directory per test so concurrent runs don't collide.
  final temp =
      Directory.systemTemp.createTempSync('fastlane_cli_session_test_');
  return temp;
}

void main() {
  group('RunSessionController prompt forwarding', () {
    test(
      'fake executor injects 2FA prompt; submitPromptResponse forwards via writeStdin',
      () async {
        final temp = _ensureTempRunner();
        addTearDown(() => temp.delete(recursive: true));
        final fakeProcess = _FakeRunningProcess();
        final executor = _PromptingExecutor(
          promptLine: 'Please enter the 6 digit code received at +1...',
          fakeProcess: fakeProcess,
        );
        final env = _buildEnvironment(executor, appRootPath: temp.path);
        final controller =
            RunSessionController(actionId: 'noop', environment: env);

        final runFuture = controller.run(confirmed: true);
        // Let the executor emit the prompt log line.
        // Give the controller's 16 ms batch timer time to fire so the
        // prompt is surfaced on the session. Bumped from 5 ms when the
        // v0.4.4 perf fix introduced log batching.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(controller.session.activePrompt, isNotNull);
        expect(
          controller.session.activePrompt!.kind,
          RunPromptKind.twoFactorCode,
        );

        // Invalid input keeps the prompt open and attaches an error.
        final err1 = await controller.submitPromptResponse('123');
        expect(err1, isNotNull);
        expect(controller.session.activePrompt, isNotNull);
        expect(controller.session.activePrompt!.validationError, isNotNull);

        // Valid input clears the prompt, records respondedAt, and forwards
        // the value to the fake child's stdin.
        final err2 = await controller.submitPromptResponse('123456');
        expect(err2, isNull);
        expect(controller.session.activePrompt, isNull);
        expect(controller.session.respondedAt, isNotNull);
        expect(fakeProcess.writes, <String>['123456']);

        executor.complete(); // let the run finish
        await runFuture;
      },
    );

    test('dismissPrompt clears prompt and sends SIGINT by default', () async {
      final temp = _ensureTempRunner();
      addTearDown(() => temp.delete(recursive: true));
      final fakeProcess = _FakeRunningProcess();
      final executor = _PromptingExecutor(
        promptLine: 'Continue? (y/n)',
        fakeProcess: fakeProcess,
      );
      final env = _buildEnvironment(executor, appRootPath: temp.path);
      final controller =
          RunSessionController(actionId: 'noop', environment: env);

      final runFuture = controller.run(confirmed: true);
      // Wait past the controller's 16 ms batch window (v0.4.4 perf fix).
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.session.activePrompt, isNotNull);

      controller.dismissPrompt();
      expect(controller.session.activePrompt, isNull);
      expect(fakeProcess.signals, contains(ProcessSignal.sigint));

      executor.complete();
      await runFuture;
    });

    test('dismissPrompt with sigint:false does not signal child', () async {
      final temp = _ensureTempRunner();
      addTearDown(() => temp.delete(recursive: true));
      final fakeProcess = _FakeRunningProcess();
      final executor = _PromptingExecutor(
        promptLine: 'Continue? (y/n)',
        fakeProcess: fakeProcess,
      );
      final env = _buildEnvironment(executor, appRootPath: temp.path);
      final controller =
          RunSessionController(actionId: 'noop', environment: env);

      final runFuture = controller.run(confirmed: true);
      // Wait past the controller's 16 ms batch window (v0.4.4 perf fix).
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.session.activePrompt, isNotNull);

      controller.dismissPrompt(sigint: false);
      expect(controller.session.activePrompt, isNull);
      expect(fakeProcess.signals, isEmpty);

      executor.complete();
      await runFuture;
    });

    test(
      'duplicate prompt lines do not overwrite the active prompt',
      () async {
        final temp = _ensureTempRunner();
        addTearDown(() => temp.delete(recursive: true));
        final fakeProcess = _FakeRunningProcess();
        final executor = _PromptingExecutor(
          promptLine: 'Please enter the 6 digit code received at +1...',
          fakeProcess: fakeProcess,
          repeatLine: true,
        );
        final env = _buildEnvironment(executor, appRootPath: temp.path);
        final controller =
            RunSessionController(actionId: 'noop', environment: env);

        final runFuture = controller.run(confirmed: true);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final firstPrompt = controller.session.activePrompt;
        expect(firstPrompt, isNotNull);
        // The fake fires the prompt line twice — the second should be a
        // no-op for activePrompt (same identity preserved).
        expect(identical(controller.session.activePrompt, firstPrompt), isTrue);

        executor.complete();
        await runFuture;
      },
    );
  });

  group('RunSessionController log batching + ring buffer', () {
    test(
      '1000 rapid log lines collapse into a small number of notifyListeners',
      () async {
        final temp = _ensureTempRunner();
        addTearDown(() => temp.delete(recursive: true));
        final fakeProcess = _FakeRunningProcess();
        final executor = _BurstExecutor(
          fakeProcess: fakeProcess,
          burstSize: 1000,
        );
        final env = _buildEnvironment(executor, appRootPath: temp.path);
        final controller =
            RunSessionController(actionId: 'noop', environment: env);

        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        final runFuture = controller.run(confirmed: true);
        executor.complete();
        await runFuture;
        // Force a final flush in case the run finished before the last 16 ms
        // timer would have fired naturally.
        controller.debugFlushPendingLogs();

        // 1000 inbound lines: with the 16 ms batch window, even the
        // worst-case (sub-millisecond burst) collapses to a small number of
        // emits. The hard cap is generous (40) to keep the test stable under
        // jittery test schedulers. Pre-v0.4.4 this would have been 1000+.
        expect(
          notifyCount,
          lessThan(40),
          reason: 'expected batched notifyListeners, got $notifyCount',
        );
        // The ring buffer cap is honoured.
        expect(controller.session.logs.length, lessThanOrEqualTo(300));
        // Last line is the exit-code summary appended at run() completion;
        // the line immediately before it should be the final burst entry.
        expect(controller.session.logs.last.message, contains('Exit code: 0'));
        expect(
          controller.session.logs[controller.session.logs.length - 2].message,
          contains('line 999'),
        );
      },
    );

    test('ring buffer cap drops oldest log entries beyond 300', () async {
      final temp = _ensureTempRunner();
      addTearDown(() => temp.delete(recursive: true));
      final fakeProcess = _FakeRunningProcess();
      final executor = _BurstExecutor(
        fakeProcess: fakeProcess,
        burstSize: 500,
      );
      final env = _buildEnvironment(executor, appRootPath: temp.path);
      final controller =
          RunSessionController(actionId: 'noop', environment: env);
      final runFuture = controller.run(confirmed: true);
      executor.complete();
      await runFuture;
      controller.debugFlushPendingLogs();

      // 500 input lines + 1 displayCommand line + 1 exit-code line. The cap
      // is 300 + we drop the oldest, so the visible log starts well after
      // 'line 0'.
      expect(controller.session.logs.length, 300);
      final firstMessage = controller.session.logs.first.message;
      expect(firstMessage, isNot(contains('line 0')));
      expect(controller.session.logs.last.message, contains('Exit code: 0'));
    });
  });
}

/// Test executor that emits [burstSize] log lines synchronously, then parks
/// until `complete()` is called. Models the worst-case "100+ lines/sec
/// xcodebuild" stream that triggered the W9 perf bottleneck.
class _BurstExecutor implements CommandExecutionService {
  _BurstExecutor({required this.fakeProcess, required this.burstSize});

  final _FakeRunningProcess fakeProcess;
  final int burstSize;
  final Completer<void> _completion = Completer<void>();

  void complete() {
    if (!_completion.isCompleted) _completion.complete();
  }

  @override
  Future<CommandExecutionResult> run(
    CommandRequest request, {
    required bool dryRun,
    required void Function(CommandLogEvent event) onLog,
    void Function(RunningProcess process)? onProcess,
  }) async {
    onProcess?.call(fakeProcess);
    for (var i = 0; i < burstSize; i++) {
      onLog(CommandLogEvent(message: 'line $i', isError: false));
    }
    await _completion.future;
    return const CommandExecutionResult(exitCode: 0, wasDryRun: false);
  }
}

/// A test-only executor that emits a prompt log line, attaches a fake
/// process, and parks until `complete()` is called. Lets us deterministically
/// drive the controller's prompt-forwarding loop without spawning a real
/// process.
class _PromptingExecutor implements CommandExecutionService {
  _PromptingExecutor({
    required this.promptLine,
    required this.fakeProcess,
    this.repeatLine = false,
  });

  final String promptLine;
  final _FakeRunningProcess fakeProcess;
  final bool repeatLine;
  final Completer<void> _completion = Completer<void>();

  void complete() {
    if (!_completion.isCompleted) _completion.complete();
  }

  @override
  Future<CommandExecutionResult> run(
    CommandRequest request, {
    required bool dryRun,
    required void Function(CommandLogEvent event) onLog,
    void Function(RunningProcess process)? onProcess,
  }) async {
    onProcess?.call(fakeProcess);
    onLog(CommandLogEvent(message: promptLine, isError: false));
    if (repeatLine) {
      onLog(CommandLogEvent(message: promptLine, isError: false));
    }
    await _completion.future;
    return const CommandExecutionResult(exitCode: 0, wasDryRun: false);
  }
}

class _FakeRunningProcess implements RunningProcess {
  final List<String> writes = <String>[];
  final List<ProcessSignal> signals = <ProcessSignal>[];

  @override
  int get pid => 12345;

  @override
  Future<bool> writeStdin(String line) async {
    writes.add(line);
    return true;
  }

  @override
  bool signal([ProcessSignal signal = ProcessSignal.sigint]) {
    signals.add(signal);
    return true;
  }
}
