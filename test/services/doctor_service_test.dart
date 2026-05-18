import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/profile_factory.dart';

void main() {
  group('DoctorService.runFull', () {
    late Directory tempCache;

    setUp(() async {
      tempCache = await Directory.systemTemp.createTemp('doctor_svc_');
    });

    tearDown(() async {
      if (tempCache.existsSync()) {
        await tempCache.delete(recursive: true);
      }
    });

    DoctorService buildService({
      required _FakeProcessRunner runner,
      Map<String, String> environment = const <String, String>{},
      String? cachePathOverride,
    }) {
      final cache = _FixedBundleCache(
        cachePathOverride ?? p.join(tempCache.path, 'cache'),
      );
      return DoctorService(
        processRunner: runner,
        bundleCache: cache,
        runnerResolver: const RunnerResolver(),
        environment: environment,
      );
    }

    test('green path: fastlane + ruby + bundle cache all OK', () async {
      // Materialize a faux bundle cache layout: <cachePath>/ruby/3.2.0/gems/a-1.0
      final cachePath = p.join(tempCache.path, 'cache');
      final gemDir =
          Directory(p.join(cachePath, 'ruby', '3.2.0', 'gems', 'fastlane-2.226.0'))
            ..createSync(recursive: true);
      File(p.join(cachePath, 'Gemfile.lock')).writeAsStringSync('GEM');
      expect(gemDir.existsSync(), isTrue);

      final runner = _FakeProcessRunner(<_Cmd, ProcessRunResult>{
        const _Cmd('fastlane', <String>['--version']): const ProcessRunResult(
          exitCode: 0,
          stdout: 'fastlane 2.226.0\n',
          stderr: '',
        ),
        const _Cmd('ruby', <String>['--version']): const ProcessRunResult(
          exitCode: 0,
          stdout: 'ruby 3.2.4 (2024-04-23 revision 1)\n',
          stderr: '',
        ),
      });

      final service = buildService(runner: runner, cachePathOverride: cachePath);
      final report = await service.runFull();

      expect(report.entries, hasLength(3));
      expect(report.entries[0].status, DoctorStatus.ok);
      expect(report.entries[0].name, 'fastlane');
      expect(report.entries[0].detail, contains('2.226.0'));
      expect(report.entries[1].status, DoctorStatus.ok);
      expect(report.entries[1].detail, '3.2.4');
      expect(report.entries[2].status, DoctorStatus.ok);
      expect(report.entries[2].detail, contains('1 gems'));
      expect(report.hasErrors, isFalse);
      expect(report.errorCount, 0);
    });

    test('fastlane not found is an error', () async {
      final runner = _FakeProcessRunner(<_Cmd, ProcessRunResult>{
        const _Cmd('ruby', <String>['--version']): const ProcessRunResult(
          exitCode: 0,
          stdout: 'ruby 3.2.4\n',
          stderr: '',
        ),
      })..throwNotFoundFor.add('fastlane');

      final service = buildService(runner: runner);
      final report = await service.runFull();
      final entry = report.entries.firstWhere((e) => e.name == 'fastlane');
      expect(entry.status, DoctorStatus.error);
      expect(entry.detail, contains('install fastlane'));
      expect(report.hasErrors, isTrue);
    });

    test('ruby older than 3.2 is an error with hint', () async {
      final runner = _FakeProcessRunner(<_Cmd, ProcessRunResult>{
        const _Cmd('fastlane', <String>['--version']): const ProcessRunResult(
          exitCode: 0,
          stdout: 'fastlane 2.0.0\n',
          stderr: '',
        ),
        const _Cmd('ruby', <String>['--version']): const ProcessRunResult(
          exitCode: 0,
          stdout: 'ruby 3.1.4\n',
          stderr: '',
        ),
      });
      final service = buildService(runner: runner);
      final report = await service.runFull();
      final ruby = report.entries.firstWhere((e) => e.name == 'ruby');
      expect(ruby.status, DoctorStatus.error);
      expect(ruby.detail, contains('3.1.4'));
      expect(ruby.detail, contains('>= 3.2'));
      expect(report.hasErrors, isTrue);
    });

    test('bundle cache absent → warning, not error', () async {
      final cachePath = p.join(tempCache.path, 'definitely-not-here');
      final runner = _FakeProcessRunner(<_Cmd, ProcessRunResult>{
        const _Cmd('fastlane', <String>['--version']): const ProcessRunResult(
          exitCode: 0,
          stdout: 'fastlane 2.226.0\n',
          stderr: '',
        ),
        const _Cmd('ruby', <String>['--version']): const ProcessRunResult(
          exitCode: 0,
          stdout: 'ruby 3.2.4\n',
          stderr: '',
        ),
      });
      final service = buildService(runner: runner, cachePathOverride: cachePath);
      final report = await service.runFull();
      final bundle = report.entries.firstWhere((e) => e.name == 'bundle cache');
      expect(bundle.status, DoctorStatus.warning);
      expect(report.hasErrors, isFalse);
    });

    test('iOS credentials warning when no env vars set', () async {
      final runner = _greenRunner();
      final profile = createTestProfile(
        appRootPath: tempCache.path,
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
      final service = buildService(runner: runner);
      final report = await service.runFull(profile: profile);
      final creds =
          report.entries.firstWhere((e) => e.name == 'iOS credentials');
      expect(creds.status, DoctorStatus.warning);
      expect(creds.detail, contains('APP_STORE_CONNECT_API_KEY_JSON_PATH'));
      final bundleId = report.entries.firstWhere((e) => e.name == 'iOS bundle id');
      expect(bundleId.status, DoctorStatus.warning);
      expect(report.hasErrors, isFalse);
    });

    test('iOS credentials OK when JSON key path set', () async {
      final runner = _greenRunner();
      final profile = _iosProfile(tempCache.path);
      final service = buildService(
        runner: runner,
        environment: <String, String>{
          'APP_STORE_CONNECT_API_KEY_JSON_PATH': '/tmp/asc.json',
          'IOS_APP_IDENTIFIER': 'com.example.app',
        },
      );
      final report = await service.runFull(profile: profile);
      final creds =
          report.entries.firstWhere((e) => e.name == 'iOS credentials');
      expect(creds.status, DoctorStatus.ok);
      final bundleId = report.entries.firstWhere((e) => e.name == 'iOS bundle id');
      expect(bundleId.status, DoctorStatus.ok);
      expect(bundleId.detail, contains('IOS_APP_IDENTIFIER'));
    });

    test('iOS credentials OK with p8 triplet', () async {
      final runner = _greenRunner();
      final profile = _iosProfile(tempCache.path);
      final service = buildService(
        runner: runner,
        environment: const <String, String>{
          'APP_STORE_CONNECT_API_KEY_ID': 'ABC',
          'APP_STORE_CONNECT_API_KEY_ISSUER_ID': 'iss',
          'APP_STORE_CONNECT_API_KEY_FILEPATH': '/tmp/key.p8',
          'FASTLANE_APP_IDENTIFIER': 'com.example',
        },
      );
      final report = await service.runFull(profile: profile);
      final creds =
          report.entries.firstWhere((e) => e.name == 'iOS credentials');
      expect(creds.status, DoctorStatus.ok);
      expect(creds.detail, contains('FILEPATH'));
    });

    test('Android credentials warning + OK paths', () async {
      final runner = _greenRunner();
      final profile = createTestProfile(
        appRootPath: tempCache.path,
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>['android_release']),
        ],
        actions: <CliAction>[
          makeFastlaneAction(
            id: 'android_release',
            categoryId: 'android',
            lane: 'release',
            platform: 'android',
          ),
        ],
      );
      // First: warning
      final warnService = buildService(runner: runner);
      final warn = await warnService.runFull(profile: profile);
      final warnCreds =
          warn.entries.firstWhere((e) => e.name == 'Android credentials');
      expect(warnCreds.status, DoctorStatus.warning);

      // Second: OK
      final okService = buildService(
        runner: runner,
        environment: const <String, String>{
          'GOOGLE_PLAY_JSON_KEY_PATH': '/tmp/service.json',
          'ANDROID_PACKAGE_NAME': 'com.example.app',
        },
      );
      final ok = await okService.runFull(profile: profile);
      final okCreds =
          ok.entries.firstWhere((e) => e.name == 'Android credentials');
      expect(okCreds.status, DoctorStatus.ok);
      final pkg =
          ok.entries.firstWhere((e) => e.name == 'Android package');
      expect(pkg.status, DoctorStatus.ok);
    });

    test('no credential rows when profile has no recognizable platforms',
        () async {
      final runner = _greenRunner();
      final profile = createTestProfile(
        appRootPath: tempCache.path,
        categories: <CliCategory>[
          makeCategory(id: 'misc', actionIds: <String>['util_clean']),
        ],
        actions: <CliAction>[
          makeFastlaneAction(
            id: 'util_clean',
            categoryId: 'misc',
            lane: 'clean',
          ),
        ],
      );
      final service = buildService(runner: runner);
      final report = await service.runFull(profile: profile);
      expect(report.entries.where((e) => e.name.startsWith('iOS')), isEmpty);
      expect(
        report.entries.where((e) => e.name.startsWith('Android')),
        isEmpty,
      );
    });
  });

  group('DoctorService.ensureBundleReady', () {
    late Directory tempDir;
    late String runnerDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('doctor_boot_');
      runnerDir = p.join(tempDir.path, 'fastlane');
      Directory(runnerDir).createSync(recursive: true);
      File(p.join(runnerDir, 'Fastfile')).writeAsStringSync('# fastfile');
      File(p.join(runnerDir, 'Gemfile')).writeAsStringSync('source "x"');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('runs bundle install when cache is missing, emits notice', () async {
      final cachePath = p.join(tempDir.path, 'cache');
      final runner = _FakeProcessRunner(const <_Cmd, ProcessRunResult>{});
      final service = DoctorService(
        processRunner: runner,
        bundleCache: _FixedBundleCache(cachePath),
        runnerResolver: _StaticRunnerResolver(runnerDir),
      );

      final sink = StringBuffer();
      await service.ensureBundleReady(noticeSink: sink);

      expect(sink.toString(), contains('first-run setup'));
      expect(runner.streamingInvocations, hasLength(1));
      final invocation = runner.streamingInvocations.single;
      expect(invocation.executable, 'bundle');
      expect(invocation.arguments, containsAll(<String>['install', '--path']));
      expect(invocation.arguments, contains(cachePath));
    });

    test('memoizes — second call is a no-op', () async {
      final cachePath = p.join(tempDir.path, 'cache');
      final runner = _FakeProcessRunner(const <_Cmd, ProcessRunResult>{});
      final service = DoctorService(
        processRunner: runner,
        bundleCache: _FixedBundleCache(cachePath),
        runnerResolver: _StaticRunnerResolver(runnerDir),
      );

      final sink = StringBuffer();
      await service.ensureBundleReady(noticeSink: sink);
      await service.ensureBundleReady(noticeSink: sink);
      expect(runner.streamingInvocations, hasLength(1));
    });

    test('skips bundle install when cache already populated', () async {
      final cachePath = p.join(tempDir.path, 'cache');
      Directory(p.join(cachePath, 'ruby', '3.2.0', 'gems', 'a-1'))
          .createSync(recursive: true);

      final runner = _FakeProcessRunner(const <_Cmd, ProcessRunResult>{});
      final service = DoctorService(
        processRunner: runner,
        bundleCache: _FixedBundleCache(cachePath),
        runnerResolver: _StaticRunnerResolver(runnerDir),
      );

      final sink = StringBuffer();
      await service.ensureBundleReady(noticeSink: sink);
      expect(runner.streamingInvocations, isEmpty);
      expect(sink.toString(), isEmpty);
    });
  });
}

_FakeProcessRunner _greenRunner() {
  return _FakeProcessRunner(<_Cmd, ProcessRunResult>{
    const _Cmd('fastlane', <String>['--version']): const ProcessRunResult(
      exitCode: 0,
      stdout: 'fastlane 2.226.0\n',
      stderr: '',
    ),
    const _Cmd('ruby', <String>['--version']): const ProcessRunResult(
      exitCode: 0,
      stdout: 'ruby 3.2.4\n',
      stderr: '',
    ),
  });
}

CliProfile _iosProfile(String appRoot) {
  return createTestProfile(
    appRootPath: appRoot,
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

class _Cmd {
  const _Cmd(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;

  @override
  bool operator ==(Object other) =>
      other is _Cmd &&
      other.executable == executable &&
      _listEquals(other.arguments, arguments);

  @override
  int get hashCode => Object.hash(executable, Object.hashAll(arguments));

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _StreamingInvocation {
  _StreamingInvocation({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner(this._responses);

  final Map<_Cmd, ProcessRunResult> _responses;
  final Set<String> throwNotFoundFor = <String>{};
  final List<_StreamingInvocation> streamingInvocations =
      <_StreamingInvocation>[];

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (throwNotFoundFor.contains(executable)) {
      throw ProcessNotFoundException(executable, 'not found');
    }
    final hit = _responses[_Cmd(executable, arguments)];
    if (hit != null) return hit;
    return const ProcessRunResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<int> runStreaming(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required void Function(String line, {required bool isError}) onLog,
  }) async {
    streamingInvocations.add(_StreamingInvocation(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
    ));
    onLog('Fetching gem metadata', isError: false);
    return 0;
  }
}

class _FixedBundleCache implements BundleCache {
  _FixedBundleCache(this._path);
  final String _path;

  @override
  bool get isMacOS => true;
  @override
  bool get isLinux => false;
  @override
  Map<String, String> get environment => const <String, String>{};

  @override
  String resolvePath() => _path;

  @override
  String rubyAbi() => 'ruby-3.2.0';
}

class _StaticRunnerResolver implements RunnerResolver {
  const _StaticRunnerResolver(this._path);
  final String _path;

  @override
  Future<String> resolve({String? profileOverride}) async => _path;

  @override
  Future<String> resolveSkillsDirectory({String? profileOverride}) async =>
      p.join(p.dirname(_path), 'skills');
}
