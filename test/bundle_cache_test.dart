import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:test/test.dart';

void main() {
  group('BundleCache', () {
    group('rubyAbi', () {
      test('uses RUBY_VERSION when set', () {
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{
            'HOME': '/Users/dev',
            'RUBY_VERSION': '3.2.4',
          },
        );

        expect(cache.rubyAbi(), 'ruby-3.2.4');
      });

      test('falls back to ruby-unknown when RUBY_VERSION absent', () {
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{'HOME': '/Users/dev'},
        );

        expect(cache.rubyAbi(), 'ruby-unknown');
      });

      test('treats whitespace-only RUBY_VERSION as absent', () {
        final cache = BundleCache(
          isMacOS: false,
          isLinux: true,
          environment: const <String, String>{
            'HOME': '/home/dev',
            'RUBY_VERSION': '   ',
          },
        );

        expect(cache.rubyAbi(), 'ruby-unknown');
      });
    });

    group('resolvePath on macOS', () {
      test('uses ~/Library/Caches and ignores XDG_CACHE_HOME', () {
        final cache = BundleCache(
          isMacOS: true,
          isLinux: false,
          environment: const <String, String>{
            'HOME': '/Users/dev',
            'RUBY_VERSION': '3.2.4',
            // Even if this is set (e.g. user copied a Linux dotfile), macOS
            // must keep the Library/Caches convention so brew + Spotlight
            // exclusions behave correctly.
            'XDG_CACHE_HOME': '/tmp/xdg',
          },
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
          environment: const <String, String>{'RUBY_VERSION': '3.2.4'},
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
            'RUBY_VERSION': '3.2.4',
            'XDG_CACHE_HOME': '/var/cache/dev',
          },
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
          environment: const <String, String>{
            'HOME': '/home/dev',
            'RUBY_VERSION': '3.2.4',
          },
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
            'RUBY_VERSION': '3.2.4',
            'XDG_CACHE_HOME': '   ',
          },
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
          environment: const <String, String>{'RUBY_VERSION': '3.2.4'},
        );

        expect(cache.resolvePath, throwsStateError);
      });
    });

    group('resolvePath on unsupported platforms', () {
      test('throws UnsupportedError on Windows-like config', () {
        final cache = BundleCache(
          isMacOS: false,
          isLinux: false,
          environment: const <String, String>{
            'HOME': r'C:\Users\dev',
            'RUBY_VERSION': '3.2.4',
          },
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
