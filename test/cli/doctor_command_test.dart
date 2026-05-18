import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/profile_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/profile_factory.dart';

void main() {
  group('DoctorCommand', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('doctor_cmd_');
      File(p.join(tempDir.path, 'cli_profile.yaml'))
          .writeAsStringSync('app:');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    CliProfile sampleProfile() {
      return createTestProfile(
        appRootPath: tempDir.path,
        categories: <CliCategory>[
          makeCategory(id: 'ios', actionIds: <String>['ios_release']),
        ],
        actions: <CliAction>[
          makeFastlaneAction(
            id: 'ios_release',
            categoryId: 'ios',
            lane: 'release',
            platform: 'ios',
          ),
        ],
      );
    }

    Future<({int? exit, String stdout, String stderr})> runDoctor({
      required DoctorService service,
      List<String> args = const <String>[],
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final command = DoctorCommand(
        profileLoader: _StaticLoader(sampleProfile()),
        profileResolver: ProfileResolver(workingDirectory: tempDir),
        doctorService: service,
        stdoutSink: out,
        stderrSink: err,
        useColor: false,
      );
      final runner = CommandRunner<int>('test', 'test')..addCommand(command);
      final exit = await runner.run(<String>['doctor', ...args]);
      return (exit: exit, stdout: out.toString(), stderr: err.toString());
    }

    test('exits 0 when service reports only OK entries', () async {
      final service = _FakeDoctorService(
        report: DoctorReport(entries: <DoctorEntry>[
          const DoctorEntry(
            status: DoctorStatus.ok,
            name: 'fastlane',
            detail: '2.226.0',
          ),
          const DoctorEntry(
            status: DoctorStatus.ok,
            name: 'ruby',
            detail: '3.2.4',
          ),
        ]),
      );
      final result = await runDoctor(service: service);
      expect(result.exit, 0);
      expect(result.stdout, contains('fastlane'));
      expect(result.stdout, contains('2.226.0'));
      expect(result.stdout, contains('[OK]'));
      expect(result.stdout, contains('2 OK · 0 warnings · 0 errors'));
      expect(result.stdout, contains('Doctor passed.'));
    });

    test('exits 0 (warnings only) when no errors but some warnings', () async {
      final service = _FakeDoctorService(
        report: DoctorReport(entries: <DoctorEntry>[
          const DoctorEntry(
            status: DoctorStatus.ok,
            name: 'fastlane',
            detail: '2.226.0',
          ),
          const DoctorEntry(
            status: DoctorStatus.warning,
            name: 'iOS credentials',
            detail: 'not set',
          ),
        ]),
      );
      final result = await runDoctor(service: service);
      expect(result.exit, 0);
      expect(result.stdout, contains('[WARN]'));
      expect(result.stdout, contains('Doctor passed (warnings only).'));
    });

    test('exits 1 when any entry is an error', () async {
      final service = _FakeDoctorService(
        report: DoctorReport(entries: <DoctorEntry>[
          const DoctorEntry(
            status: DoctorStatus.error,
            name: 'ruby',
            detail: 'too old',
          ),
        ]),
      );
      final result = await runDoctor(service: service);
      expect(result.exit, 1);
      expect(result.stdout, contains('[FAIL]'));
      expect(result.stdout, contains('Doctor failed'));
    });

    test('passes the profile into the service', () async {
      final service = _FakeDoctorService(
        report: DoctorReport(entries: const <DoctorEntry>[]),
      );
      await runDoctor(service: service);
      expect(service.lastProfile, isNotNull);
      expect(service.lastProfile!.appName, 'TestApp');
    });

    test('continues without profile when resolver fails', () async {
      final freshDir = await Directory.systemTemp.createTemp('doctor_no_p_');
      try {
        final service = _FakeDoctorService(
          report: DoctorReport(entries: const <DoctorEntry>[]),
        );
        final out = StringBuffer();
        final err = StringBuffer();
        final command = DoctorCommand(
          profileLoader: _StaticLoader(sampleProfile()),
          profileResolver: ProfileResolver(workingDirectory: freshDir),
          doctorService: service,
          stdoutSink: out,
          stderrSink: err,
          useColor: false,
        );
        final runner = CommandRunner<int>('test', 'test')..addCommand(command);
        final exit = await runner.run(<String>['doctor']);
        expect(exit, 0);
        expect(service.lastProfile, isNull);
        expect(out.toString(), contains('fastlane_cli doctor'));
      } finally {
        if (freshDir.existsSync()) {
          await freshDir.delete(recursive: true);
        }
      }
    });

    test('emits ANSI codes only when useColor is true', () async {
      final report = DoctorReport(entries: const <DoctorEntry>[
        DoctorEntry(
          status: DoctorStatus.ok,
          name: 'fastlane',
          detail: '2.0.0',
        ),
      ]);
      final out = StringBuffer();
      final colored = DoctorCommand(
        profileLoader: _StaticLoader(sampleProfile()),
        profileResolver: ProfileResolver(workingDirectory: tempDir),
        doctorService: _FakeDoctorService(report: report),
        stdoutSink: out,
        stderrSink: StringBuffer(),
        useColor: true,
      );
      final runner = CommandRunner<int>('test', 'test')..addCommand(colored);
      await runner.run(<String>['doctor']);
      // ESC + [ + digits + 'm'
      expect(out.toString(), contains('['));
    });
  });
}

class _StaticLoader extends ProfileLoader {
  _StaticLoader(this._profile);
  final CliProfile _profile;

  @override
  Future<CliProfile> load(String profilePath) async => _profile;
}

class _FakeDoctorService implements DoctorService {
  _FakeDoctorService({required this.report});

  final DoctorReport report;
  CliProfile? lastProfile;

  @override
  Future<DoctorReport> runFull({CliProfile? profile}) async {
    lastProfile = profile;
    return report;
  }

  @override
  Future<void> ensureBundleReady({StringSink? noticeSink}) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
