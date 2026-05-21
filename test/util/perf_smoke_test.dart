// Synthetic benchmark for the v0.4.4 perf hotfix. Drives 5000 log lines
// through a real `RunSessionController` + fake executor and records the
// number of `notifyListeners` invocations and wall-clock duration.
//
// Tagged `perf` so it can be skipped on CI (we don't want CI runners
// asserting wall-clock budgets that depend on machine speed). Run locally
// with `fvm dart test test/util/perf_smoke_test.dart --tags perf`.

import 'dart:async';
import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart';
import 'package:fastlane_cli/src/services/guide_registry.dart';
import 'package:test/test.dart';

import '../support/profile_factory.dart';

void main() {
  test('5000-line burst stays under the W9 budget', () async {
    final temp = Directory.systemTemp.createTempSync('fastlane_cli_perf_');
    addTearDown(() => temp.delete(recursive: true));

    final profile = createTestProfile(
      appRootPath: temp.path,
      categories: <CliCategory>[
        makeCategory(id: 'general', actionIds: <String>['noop']),
      ],
      actions: <CliAction>[
        makeFastlaneAction(id: 'noop', categoryId: 'general', lane: 'noop'),
      ],
    );
    final executor = _BurstExecutor(burstSize: 5000);
    final env = FastlaneCliEnvironment(
      profile: profile,
      initialLocale: AppLocale.en,
      dryRun: true,
      commandBuilder: const CommandBuilder(),
      executionService: executor,
      preflightValidator: const PreflightValidator(),
      guideRegistry: const GuideRegistry(),
    );
    final controller =
        RunSessionController(actionId: 'noop', environment: env);

    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    final sw = Stopwatch()..start();
    final future = controller.run(confirmed: true);
    executor.complete();
    await future;
    controller.debugFlushPendingLogs();
    sw.stop();

    // Hard ceilings — generously above the observed numbers on a 2024 M3
    // (typically ~30 emits / ~120 ms wallclock).
    expect(
      notifyCount,
      lessThan(200),
      reason: 'expected batched emits, got $notifyCount',
    );
    expect(sw.elapsedMilliseconds, lessThan(2000));
    expect(controller.session.logs.length, lessThanOrEqualTo(300));

    // Print the observed numbers so the PR body can paste them.
    // ignore: avoid_print
    print(
      'PERF: 5000 appends → notifyListeners=$notifyCount, '
      'wallclock=${sw.elapsedMilliseconds} ms, '
      'final logs.length=${controller.session.logs.length}',
    );
  }, tags: <String>['perf']);
}

class _BurstExecutor implements CommandExecutionService {
  _BurstExecutor({required this.burstSize});
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
    for (var i = 0; i < burstSize; i++) {
      onLog(CommandLogEvent(message: 'line $i', isError: false));
    }
    await _completion.future;
    return const CommandExecutionResult(exitCode: 0, wasDryRun: false);
  }
}
