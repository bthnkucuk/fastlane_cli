import 'dart:io';

import 'package:path/path.dart' as p;

import 'process_runner.dart';

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
/// `<ruby-abi>` is `ruby-<version>` where `<version>` is determined, in
/// order:
///
///   1. The injected [rubyVersionOverride] (set by tests, and by callers
///      that already know the version — e.g. `DoctorService` after its own
///      `ruby --version` check).
///   2. A live probe of `ruby --version` performed via [ProcessRunner].
///      Production code uses [SystemProcessRunner] and the probe runs
///      synchronously via [Process.runSync]; tests inject a fake runner
///      and `await` [primeRubyVersion] before calling [rubyAbi] / [resolvePath].
///   3. Fallback: `ruby-unknown` plus a one-time stderr warning. The
///      `doctor` command's `ruby` check is the source of truth for "is
///      ruby installed?"; this fallback only kicks in when something has
///      gone very wrong (`ruby` not on PATH at the moment the bundle path
///      is computed).
///
/// `RUBY_VERSION` is a Ruby-internal constant — it is NOT exported as an
/// OS env var by default, so the previous behaviour ("read `RUBY_VERSION`
/// from `environment`") effectively pinned every fresh install at
/// `ruby-unknown`. This implementation probes the live ruby on PATH instead.
///
/// This class performs NO filesystem side effects (no mkdir, no stat). It
/// only computes paths from inputs and may spawn `ruby --version` once per
/// instance to discover the ABI. The caller is responsible for `mkdir -p`
/// and for actually running `bundle install`.
class BundleCache {
  /// Direct constructor. Use [BundleCache.fromPlatform] for production code
  /// and this constructor for tests that want to fully control inputs.
  ///
  /// Provide [rubyVersionOverride] to pin the ABI deterministically (the
  /// simplest path for unit tests). Provide [processRunner] to back the
  /// `ruby --version` probe with a fake.
  BundleCache({
    required this.isMacOS,
    required this.isLinux,
    required this.environment,
    ProcessRunner? processRunner,
    String? rubyVersionOverride,
  })  : _processRunner = processRunner,
        _rubyVersionOverride = rubyVersionOverride;

  /// Convenience constructor that snapshots `dart:io`'s [Platform] state and
  /// wires the production [SystemProcessRunner] so [rubyAbi] can probe
  /// `ruby --version` lazily.
  factory BundleCache.fromPlatform() {
    return BundleCache(
      isMacOS: Platform.isMacOS,
      isLinux: Platform.isLinux,
      environment: Platform.environment,
      processRunner: const SystemProcessRunner(),
    );
  }

  final bool isMacOS;
  final bool isLinux;
  final Map<String, String> environment;
  final ProcessRunner? _processRunner;
  final String? _rubyVersionOverride;

  // Memoized probe result. Empty string sentinel means "we probed and got
  // nothing"; null means "not yet probed".
  String? _cachedRubyVersion;
  bool _warnedRubyMissing = false;

  /// Asynchronously probes `ruby --version` via the injected
  /// [ProcessRunner] and caches the result. Use this from tests with a
  /// fake runner; production callers can ignore it (the synchronous
  /// fallback in [rubyAbi] handles the production path through
  /// [Process.runSync]).
  ///
  /// Safe to call multiple times — only the first call actually spawns a
  /// process. Returns the parsed `X.Y.Z` (or `null` if the probe failed).
  Future<String?> primeRubyVersion() async {
    final override = _rubyVersionOverride?.trim();
    if (override != null && override.isNotEmpty) {
      _cachedRubyVersion = override;
      return override;
    }
    final cached = _cachedRubyVersion;
    if (cached != null) {
      return cached.isEmpty ? null : cached;
    }
    final runner = _processRunner;
    if (runner == null) {
      _cachedRubyVersion = '';
      return null;
    }
    try {
      final result = await runner.run('ruby', const <String>['--version']);
      if (result.exitCode != 0) {
        _markUnknown();
        return null;
      }
      final parsed = parseRubyVersion(result.stdout);
      if (parsed == null) {
        _markUnknown();
        return null;
      }
      _cachedRubyVersion = parsed;
      return parsed;
    } on ProcessNotFoundException {
      _markUnknown();
      return null;
    }
  }

  /// Absolute path to the per-user, per-ruby-ABI bundle cache directory.
  ///
  /// Throws [UnsupportedError] when the host platform is neither macOS nor
  /// Linux. (Windows is intentionally out of scope — fastlane has a poor
  /// Windows story and brew is the target distribution channel.)
  String resolvePath() {
    final root = _cacheRoot();
    return p.join(root, 'fastlane_cli', 'bundle', rubyAbi());
  }

  /// Stable token for the current Ruby ABI. Synchronously returns the
  /// memoized probe result; if no probe has run yet and a
  /// [SystemProcessRunner] is wired, falls back to a one-shot
  /// [Process.runSync] of `ruby --version`. Other [ProcessRunner]
  /// implementations (test fakes) must be primed via [primeRubyVersion]
  /// before calling this — otherwise the abi degrades to `ruby-unknown`.
  String rubyAbi() {
    final override = _rubyVersionOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return 'ruby-$override';
    }
    final cached = _cachedRubyVersion;
    if (cached != null) {
      return cached.isEmpty ? 'ruby-unknown' : 'ruby-$cached';
    }

    final runner = _processRunner;
    if (runner is SystemProcessRunner) {
      final version = _probeSync();
      if (version == null) {
        _markUnknown();
        return 'ruby-unknown';
      }
      _cachedRubyVersion = version;
      return 'ruby-$version';
    }

    // No runner or non-system runner that wasn't primed. Mark unknown so
    // the warning only fires once per instance.
    _markUnknown();
    return 'ruby-unknown';
  }

  String? _probeSync() {
    try {
      final result = Process.runSync(
        'ruby',
        const <String>['--version'],
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        return null;
      }
      return parseRubyVersion(result.stdout.toString());
    } on ProcessException {
      return null;
    }
  }

  void _markUnknown() {
    _cachedRubyVersion = '';
    if (_warnedRubyMissing) return;
    _warnedRubyMissing = true;
    stderr.writeln(
      'fastlane_cli: warning — could not determine Ruby version via '
      '`ruby --version`; bundle cache will be placed under `ruby-unknown`. '
      'Run `fastlane_cli doctor` to diagnose.',
    );
  }

  /// Parses "ruby 3.2.4 (2024-04-23 …)" → "3.2.4". Returns `null` when the
  /// output cannot be matched. Visible for tests.
  static String? parseRubyVersion(String stdout) {
    final match = RegExp(r'ruby\s+(\d+\.\d+(?:\.\d+)?)').firstMatch(stdout);
    if (match != null) {
      return match.group(1);
    }
    final loose = RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(stdout);
    return loose?.group(1);
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
