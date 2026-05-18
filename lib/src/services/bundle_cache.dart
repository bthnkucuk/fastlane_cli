import 'dart:io';

import 'package:path/path.dart' as p;

/// Pure resolver for the user-level `bundle install --path` location.
///
/// The fastlane runner's `Gemfile` is slim (see `fastlane/Gemfile`) and must
/// NOT install into `fastlane/vendor/` — that path bakes the install into the
/// brew Cellar, which is read-only and platform-pinned. Instead we point
/// `BUNDLE_PATH` at a per-user, per-ruby-ABI cache:
///
/// - macOS : `~/Library/Caches/fastlane_cli/bundle/<ruby-abi>`
/// - Linux : `$XDG_CACHE_HOME/fastlane_cli/bundle/<ruby-abi>`
///           (falls back to `~/.cache/fastlane_cli/bundle/<ruby-abi>`)
///
/// `<ruby-abi>` is `ruby-<RUBY_VERSION>` when the `RUBY_VERSION` environment
/// variable is set (rbenv/asdf shells export this); otherwise it falls back
/// to `ruby-unknown`. Track B2's `doctor` subcommand is expected to backfill
/// `RUBY_VERSION` from `ruby -e 'puts RUBY_VERSION'` before invoking lanes,
/// so this fallback is mostly a safety net.
///
/// This class is pure: it performs NO filesystem side effects (no mkdir, no
/// stat). It only computes paths from inputs. The caller (a future
/// `doctor`/`setup` flow, Track B2) is responsible for `mkdir -p` and for
/// actually running `bundle install`.
class BundleCache {
  const BundleCache({
    required this.isMacOS,
    required this.isLinux,
    required this.environment,
  });

  /// Convenience constructor that snapshots `dart:io`'s [Platform] state.
  factory BundleCache.fromPlatform() {
    return BundleCache(
      isMacOS: Platform.isMacOS,
      isLinux: Platform.isLinux,
      environment: Platform.environment,
    );
  }

  final bool isMacOS;
  final bool isLinux;
  final Map<String, String> environment;

  /// Absolute path to the per-user, per-ruby-ABI bundle cache directory.
  ///
  /// Throws [UnsupportedError] when the host platform is neither macOS nor
  /// Linux. (Windows is intentionally out of scope — fastlane has a poor
  /// Windows story and brew is the target distribution channel.)
  String resolvePath() {
    final root = _cacheRoot();
    return p.join(root, 'fastlane_cli', 'bundle', rubyAbi());
  }

  /// Stable token for the current Ruby ABI. Prefers `RUBY_VERSION` from the
  /// environment; falls back to `ruby-unknown` so the path remains valid
  /// even before B2 wires the doctor probe.
  String rubyAbi() {
    final raw = environment['RUBY_VERSION']?.trim() ?? '';
    if (raw.isEmpty) {
      return 'ruby-unknown';
    }
    return 'ruby-$raw';
  }

  String _cacheRoot() {
    if (isMacOS) {
      final home = _requireHome();
      return p.join(home, 'Library', 'Caches');
    }
    if (isLinux) {
      final xdg = environment['XDG_CACHE_HOME']?.trim() ?? '';
      if (xdg.isNotEmpty) {
        return xdg;
      }
      final home = _requireHome();
      return p.join(home, '.cache');
    }
    throw UnsupportedError(
      'fastlane_cli bundle cache is only defined for macOS and Linux.',
    );
  }

  String _requireHome() {
    final home = environment['HOME']?.trim() ?? '';
    if (home.isEmpty) {
      throw StateError(
        'HOME environment variable is not set; cannot resolve bundle cache.',
      );
    }
    return home;
  }
}
