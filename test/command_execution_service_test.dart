import 'dart:io';

import 'package:fastlane_cli/src/model/command_request.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessCommandExecutionService', () {
    test('dry run emits display command and succeeds', () async {
      const service = ProcessCommandExecutionService();
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
      expect(events, hasLength(1));
      expect(events.single.message, contains('[dry-run]'));
      expect(
        events.single.message,
        contains('bundle exec fastlane android lane'),
      );
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
  });
}
