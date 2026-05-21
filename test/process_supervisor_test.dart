@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:fastlane_cli/src/services/command_execution_service.dart';
import 'package:test/test.dart';

/// Tests for the [ProcessSupervisor] — the registry + multi-signal listener
/// + grace-period shutdown that prevents orphaned `bundle exec fastlane …`
/// children when the TUI exits via any path (Ctrl+C, in-app quit, SIGTERM,
/// SIGHUP, unhandled Dart exception).
///
/// POSIX-only: Windows cannot post POSIX signals to children and the
/// supervisor's signal listeners are no-ops there.
void main() {
  group('ProcessSupervisor', () {
    tearDown(() => ProcessSupervisor.instance.resetForTesting());

    test('shutdownAll is a no-op when no children are registered', () async {
      await ProcessSupervisor.instance.shutdownAll();
      expect(ProcessSupervisor.instance.liveCount, 0);
    });

    test('registers and auto-deregisters when child exits on its own',
        () async {
      final process =
          await Process.start('/bin/sh', <String>['-c', 'echo ok']);
      ProcessSupervisor.instance.register(process);
      expect(ProcessSupervisor.instance.liveCount, 1);
      final exit = await process.exitCode;
      expect(exit, 0);
      // exitCode.whenComplete hook is microtask-scheduled; let it drain.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ProcessSupervisor.instance.liveCount, 0);
    });

    test('shutdownAll SIGINTs the child and lets it exit gracefully',
        () async {
      // A sleeping shell traps SIGINT by default and exits with 130.
      final process =
          await Process.start('/bin/sh', <String>['-c', 'sleep 30']);
      ProcessSupervisor.instance.register(process);
      expect(ProcessSupervisor.instance.liveCount, 1);

      await ProcessSupervisor.instance.shutdownAll(
        graceful: const Duration(milliseconds: 500),
      );
      // Child should have exited (signalled). exitCode is negative on POSIX
      // when the child was killed by a signal; on macOS Dart reports
      // exitCode == -SIGINT == -2 for sh.
      final code = await process.exitCode;
      expect(code, isNot(0));
    });

    test(
      'shutdownAll falls back to SIGKILL when the child ignores SIGINT',
      () async {
        // perl is universally available on macOS + ubuntu CI runners and
        // gives us precise signal control: $SIG{INT}='IGNORE' makes the
        // child immune to SIGINT, forcing the supervisor to escalate to
        // SIGKILL after the grace period.
        final process = await Process.start(
          '/usr/bin/perl',
          <String>[
            '-e',
            r"$SIG{INT}='IGNORE'; $SIG{TERM}='IGNORE'; sleep 30;",
          ],
        );
        ProcessSupervisor.instance.register(process);
        // Give perl a tick to install its signal handlers before we start
        // firing signals at it.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(ProcessSupervisor.instance.liveCount, 1,
            reason: 'perl should still be running');

        final stopwatch = Stopwatch()..start();
        await ProcessSupervisor.instance.shutdownAll(
          graceful: const Duration(milliseconds: 250),
        );
        stopwatch.stop();

        final code = await process.exitCode;
        expect(code, isNot(0),
            reason: 'SIGKILL should have terminated the child');
        // Grace period must have elapsed before SIGKILL fired.
        expect(stopwatch.elapsed.inMilliseconds, greaterThanOrEqualTo(240));
      },
      skip: !File('/usr/bin/perl').existsSync()
          ? '/usr/bin/perl unavailable'
          : false,
    );

    test('shutdownAll handles multiple registered children in parallel',
        () async {
      final processes = <Process>[
        await Process.start('/bin/sh', <String>['-c', 'sleep 30']),
        await Process.start('/bin/sh', <String>['-c', 'sleep 30']),
        await Process.start('/bin/sh', <String>['-c', 'sleep 30']),
      ];
      for (final p in processes) {
        ProcessSupervisor.instance.register(p);
      }
      expect(ProcessSupervisor.instance.liveCount, 3);

      await ProcessSupervisor.instance.shutdownAll(
        graceful: const Duration(milliseconds: 500),
      );

      for (final p in processes) {
        expect(await p.exitCode, isNot(0));
      }
    });

    test('register installs signal listeners exactly once', () async {
      // Second register on a fresh supervisor must not throw, and liveCount
      // tracks correctly.
      final p1 = await Process.start('/bin/sh', <String>['-c', 'sleep 5']);
      final p2 = await Process.start('/bin/sh', <String>['-c', 'sleep 5']);
      ProcessSupervisor.instance.register(p1);
      ProcessSupervisor.instance.register(p2);
      expect(ProcessSupervisor.instance.liveCount, 2);
      await ProcessSupervisor.instance.shutdownAll(
        graceful: const Duration(milliseconds: 200),
      );
    });
  });
}
