import 'dart:io';

import 'package:fastlane_cli/src/model/command_request.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessCommandExecutionService', () {
    test('dry run emits display command and succeeds', () async {
      final service = ProcessCommandExecutionService();
      final request = CommandRequest(
        executable: 'bundle',
        arguments: <String>['exec', 'fastlane', 'android', 'lane'],
        workingDirectory: '/tmp',
        environment: const <String, String>{},
      );

      final events = <CommandLogEvent>[];
      final result = await service.run(
        request,
        dryRun: true,
        onLog: events.add,
      );

      expect(result.exitCode, 0);
      expect(result.wasDryRun, isTrue);
      // cwd + (no env keys) + display = 2 lines when env is empty.
      expect(events.length, greaterThanOrEqualTo(2));
      expect(events.any((e) => e.message.contains('[dry-run] cwd=/tmp')), isTrue);
      expect(
        events.any((e) =>
            e.message.contains('bundle exec fastlane android lane')),
        isTrue,
      );
    });

    test('dry run redacts secret-looking env keys and prints env block',
        () async {
      final service = ProcessCommandExecutionService();
      final request = CommandRequest(
        executable: 'bundle',
        arguments: const <String>['exec', 'fastlane', 'noop'],
        workingDirectory: '/tmp',
        environment: const <String, String>{
          'IOS_APP_IDENTIFIER': 'com.example.app',
          'ANDROID_PACKAGE_NAME': 'com.example.app',
          'APP_STORE_CONNECT_API_KEY_JSON_PATH': '/secret/path.json',
          'GOOGLE_PLAY_JSON_KEY_DATA': '{"secret":"value"}',
          'FASTLANE_PASSWORD': 'hunter2',
          'PLAIN_VAR': 'visible',
        },
      );

      final events = <CommandLogEvent>[];
      await service.run(request, dryRun: true, onLog: events.add);

      final lines = events.map((e) => e.message).toList();
      // Identifier-style keys are not redacted.
      expect(lines, contains(contains('IOS_APP_IDENTIFIER=com.example.app')));
      expect(
        lines,
        contains(contains('ANDROID_PACKAGE_NAME=com.example.app')),
      );
      expect(lines, contains(contains('PLAIN_VAR=visible')));
      // Secret-looking keys are redacted; their values must not appear.
      expect(
        lines.any((l) => l.contains('APP_STORE_CONNECT_API_KEY_JSON_PATH=***')),
        isTrue,
      );
      expect(
        lines.any((l) => l.contains('GOOGLE_PLAY_JSON_KEY_DATA=***')),
        isTrue,
      );
      expect(lines.any((l) => l.contains('FASTLANE_PASSWORD=***')), isTrue);
      for (final line in lines) {
        expect(line.contains('/secret/path.json'), isFalse);
        expect(line.contains('hunter2'), isFalse);
        expect(line.contains('"secret":"value"'), isFalse);
      }
    });

    test(
      'executes real process on POSIX and reports exit code',
      () async {
        final service = ProcessCommandExecutionService(useUnixPty: false);
        final temp = await Directory.systemTemp.createTemp('fastlane_cli_exec');
        addTearDown(() => temp.delete(recursive: true));

        final events = <CommandLogEvent>[];
        final result = await service.run(
          CommandRequest(
            executable: '/bin/sh',
            arguments: <String>['-c', 'echo ok && exit 0'],
            workingDirectory: temp.path,
            environment: const <String, String>{},
          ),
          dryRun: false,
          onLog: events.add,
        );

        expect(result.wasDryRun, isFalse);
        expect(result.exitCode, 0);
        expect(events.any((e) => e.message == 'ok'), isTrue);
      },
      skip: Platform.isWindows ? 'POSIX shell only' : false,
    );

    test(
      'deregisters child from ProcessSupervisor on natural exit',
      () async {
        await ProcessSupervisor.instance.resetForTesting();
        final service = ProcessCommandExecutionService(useUnixPty: false);
        final temp =
            await Directory.systemTemp.createTemp('fastlane_cli_exec_reg');
        addTearDown(() => temp.delete(recursive: true));

        final events = <CommandLogEvent>[];
        await service.run(
          CommandRequest(
            executable: '/bin/sh',
            arguments: <String>['-c', 'echo done'],
            workingDirectory: temp.path,
            environment: const <String, String>{},
          ),
          dryRun: false,
          onLog: events.add,
        );

        // Allow the auto-deregister microtask to drain.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(ProcessSupervisor.instance.liveCount, 0);
      },
      skip: Platform.isWindows ? 'POSIX shell only' : false,
    );
  });
}
