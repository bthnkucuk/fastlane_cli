import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:test/test.dart';

void main() {
  group('BundleCache', () {
    group('rubyAbi', () {
      test('uses rubyVersionOverride when set', () {
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{'HOME': '/Users/dev'},
          rubyVersionOverride: '3.2.4',
        );

        expect(cache.rubyAbi(), 'ruby-3.2.4');
      });

      test('treats whitespace-only rubyVersionOverride as absent', () {
        final cache = BundleCache(
          isMacOS: false,
          isLinux: true,
          environment: const <String, String>{'HOME': '/home/dev'},
          rubyVersionOverride: '   ',
        );

        // No process runner injected → falls back to unknown.
        expect(cache.rubyAbi(), 'ruby-unknown');
      });

      test(
          'falls back to ruby-unknown when no override and no probe available',
          () {
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{'HOME': '/Users/dev'},
        );

        expect(cache.rubyAbi(), 'ruby-unknown');
      });

      test('ignores legacy RUBY_VERSION env var (intentional regression-fix)',
          () {
        // Prior to v0.2.1 BundleCache read RUBY_VERSION from the environment.
        // That value is never set as an OS env var (it's a Ruby-internal
        // constant), so the path always landed at `ruby-unknown` in practice.
        // After the fix, only an explicit override or a live `ruby --version`
        // probe drives the abi. This test pins that behaviour.
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{
            'HOME': '/Users/dev',
            'RUBY_VERSION': '3.2.4',
          },
        );

        expect(cache.rubyAbi(), 'ruby-unknown');
      });

      test('uses fake ProcessRunner output after primeRubyVersion', () async {
        final runner = _FakeProcessRunner.ok('ruby 3.3.1 (2024-12-01)');
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{'HOME': '/Users/dev'},
          processRunner: runner,
        );

        final primed = await cache.primeRubyVersion();
        expect(primed, '3.3.1');
        expect(cache.rubyAbi(), 'ruby-3.3.1');
        expect(runner.runInvocations, hasLength(1));
        // A second prime is a memoized no-op.
        await cache.primeRubyVersion();
        expect(runner.runInvocations, hasLength(1));
      });

      test('falls back to ruby-unknown when probe reports missing ruby',
          () async {
        final runner = _FakeProcessRunner.notFound('ruby');
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{'HOME': '/Users/dev'},
          processRunner: runner,
        );

        final primed = await cache.primeRubyVersion();
        expect(primed, isNull);
        expect(cache.rubyAbi(), 'ruby-unknown');
      });

      test('falls back to ruby-unknown when probe exits non-zero', () async {
        final runner = _FakeProcessRunner(
          const ProcessRunResult(
            exitCode: 1,
            stdout: '',
            stderr: 'broken',
          ),
        );
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{'HOME': '/Users/dev'},
          processRunner: runner,
        );

        final primed = await cache.primeRubyVersion();
        expect(primed, isNull);
        expect(cache.rubyAbi(), 'ruby-unknown');
      });

      test('parseRubyVersion handles assorted shapes', () {
        expect(
          BundleCache.parseRubyVersion('ruby 3.2.4 (2024-04-23) [arm64-darwin]'),
          '3.2.4',
        );
        expect(BundleCache.parseRubyVersion('ruby 3.3'), '3.3');
        expect(BundleCache.parseRubyVersion('garbage'), isNull);
      });
    });

    group('resolvePath on macOS', () {
      test('uses ~/Library/Caches and ignores XDG_CACHE_HOME', () {
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{
            'HOME': '/Users/dev',
            // Even if this is set (e.g. user copied a Linux dotfile), macOS
            // must keep the Library/Caches convention so brew + Spotlight
            // exclusions behave correctly.
            'XDG_CACHE_HOME': '/tmp/xdg',
          },
          rubyVersionOverride: '3.2.4',
        );

        expect(
          cache.resolvePath(),
          '/Users/dev/Library/Caches/fastlane_cli/bundle/ruby-3.2.4',
        );
      });

      test('throws StateError when HOME is missing', () {
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{},
          rubyVersionOverride: '3.2.4',
        );

        expect(cache.resolvePath, throwsStateError);
      });
    });

    group('resolvePath on Linux', () {
      test('uses XDG_CACHE_HOME when set', () {
        final cache = BundleCache(
          isMacOS: false,
          isLinux: true,
          environment: const <String, String>{
            'HOME': '/home/dev',
            'XDG_CACHE_HOME': '/var/cache/dev',
          },
          rubyVersionOverride: '3.2.4',
        );

        expect(
          cache.resolvePath(),
          '/var/cache/dev/fastlane_cli/bundle/ruby-3.2.4',
        );
      });

      test('falls back to ~/.cache when XDG_CACHE_HOME absent', () {
        final cache = BundleCache(
          isMacOS: false,
          isLinux: true,
          environment: const <String, String>{'HOME': '/home/dev'},
          rubyVersionOverride: '3.2.4',
        );

        expect(
          cache.resolvePath(),
          '/home/dev/.cache/fastlane_cli/bundle/ruby-3.2.4',
        );
      });

      test('treats whitespace-only XDG_CACHE_HOME as unset', () {
        final cache = BundleCache(
          isMacOS: false,
          isLinux: true,
          environment: const <String, String>{
            'HOME': '/home/dev',
            'XDG_CACHE_HOME': '   ',
          },
          rubyVersionOverride: '3.2.4',
        );

        expect(
          cache.resolvePath(),
          '/home/dev/.cache/fastlane_cli/bundle/ruby-3.2.4',
        );
      });

      test('throws StateError when both HOME and XDG_CACHE_HOME missing', () {
        final cache = BundleCache(
          isMacOS: false,
          isLinux: true,
          environment: const <String, String>{},
          rubyVersionOverride: '3.2.4',
        );

        expect(cache.resolvePath, throwsStateError);
      });
    });

    group('resolvePath on unsupported platforms', () {
      test('throws UnsupportedError on Windows-like config', () {
        final cache = BundleCache(
          isMacOS: false,
          isLinux: false,
          environment: const <String, String>{'HOME': r'C:\Users\dev'},
          rubyVersionOverride: '3.2.4',
        );

        expect(cache.resolvePath, throwsA(isA<UnsupportedError>()));
      });
    });

    group('fromPlatform', () {
      test('snapshots the runtime Platform without throwing', () {
        // Smoke test: instantiation should succeed on the dev host (macOS or
        // Linux). We don't assert the value because it depends on the
        // machine running the test.
        expect(BundleCache.fromPlatform, returnsNormally);
      });
    });
  });
}

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner(ProcessRunResult response)
      : _response = response,
        _throwNotFound = false;

  factory _FakeProcessRunner.ok(String stdout) => _FakeProcessRunner(
        ProcessRunResult(exitCode: 0, stdout: stdout, stderr: ''),
      );

  factory _FakeProcessRunner.notFound(String executable) {
    final runner = _FakeProcessRunner.__notFound();
    return runner;
  }

  _FakeProcessRunner.__notFound()
      : _response = const ProcessRunResult(exitCode: 127, stdout: '', stderr: ''),
        _throwNotFound = true;

  final ProcessRunResult _response;
  final bool _throwNotFound;
  final List<List<Object?>> runInvocations = <List<Object?>>[];

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    runInvocations.add(<Object?>[executable, arguments]);
    if (_throwNotFound) {
      throw ProcessNotFoundException(executable, 'fake-enoent');
    }
    return _response;
  }

  @override
  Future<int> runStreaming(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required void Function(String line, {required bool isError}) onLog,
  }) async {
    throw UnimplementedError();
  }
}
