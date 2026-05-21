import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/cli_profile.dart';
import 'bundle_cache.dart';
import 'process_runner.dart';
import 'runner_resolver.dart';

/// Severity of a single doctor check result.
enum DoctorStatus { ok, warning, error }

/// Single line item in a doctor report (one row of the printed table).
class DoctorEntry {
  const DoctorEntry({
    required this.status,
    required this.name,
    required this.detail,
  });

  final DoctorStatus status;
  final String name;
  final String detail;
}

/// Aggregate result of [DoctorService.runFull].
class DoctorReport {
  DoctorReport({required this.entries});

  final List<DoctorEntry> entries;

  int get okCount =>
      entries.where((e) => e.status == DoctorStatus.ok).length;
  int get warningCount =>
      entries.where((e) => e.status == DoctorStatus.warning).length;
  int get errorCount =>
      entries.where((e) => e.status == DoctorStatus.error).length;

  bool get hasErrors => errorCount > 0;
}

/// Environment-health checks for `fastlane_cli doctor` plus a one-shot bundle
/// bootstrap that lane runners call before their first spawn.
///
/// Pure logic — every I/O surface is injected:
/// - [ProcessRunner] for `fastlane --version`, `ruby --version`, `bundle ...`.
/// - [BundleCache] for the per-user, per-ruby-ABI bundle path.
/// - [RunnerResolver] for the bundled fastlane runner Gemfile.
/// - File system probes are localized to dedicated helpers so a future
///   in-memory FS abstraction can swap them out.
class DoctorService {
  DoctorService({
    ProcessRunner? processRunner,
    BundleCache? bundleCache,
    RunnerResolver? runnerResolver,
    Map<String, String>? environment,
  }) : _processRunner = processRunner ?? const SystemProcessRunner(),
       _bundleCache = bundleCache,
       _runnerResolver = runnerResolver ?? const RunnerResolver(),
       _environment = environment ?? Platform.environment;

  final ProcessRunner _processRunner;
  final BundleCache? _bundleCache;
  final RunnerResolver _runnerResolver;
  final Map<String, String> _environment;

  // Track whether ensureBundleReady already finished in this process so
  // repeated lane invocations from the TUI don't probe / install on every
  // run. Guarded by a Completer to serialize concurrent callers.
  Completer<void>? _bootstrap;

  BundleCache get _resolvedBundleCache =>
      _bundleCache ?? BundleCache.fromPlatform();

  /// Full doctor sweep used by `fastlane_cli doctor`.
  ///
  /// [profile] drives credential-check platform inference (action ids
  /// starting with `ios_` / `android_`). Pass `null` from contexts that
  /// don't have a profile (we just skip the credential block).
  Future<DoctorReport> runFull({CliProfile? profile}) async {
    final entries = <DoctorEntry>[];

    entries.add(await _checkFastlane());
    final rubyEntry = await _checkRuby();
    entries.add(rubyEntry);
    entries.add(await _checkBundleCache());

    if (profile != null) {
      entries.add(_checkAppRoot(profile));
      entries.add(_checkFastlaneDir(profile));
      final platforms = _inferPlatforms(profile);
      if (platforms.contains(_Platform.ios)) {
        entries.add(_checkIosCredentials());
        entries.add(_checkIosIdentifier());
      }
      if (platforms.contains(_Platform.android)) {
        entries.add(_checkAndroidCredentials());
        entries.add(_checkAndroidIdentifier());
      }
    }

    return DoctorReport(entries: entries);
  }

  /// Bootstrap helper that lane runners call before spawning fastlane.
  ///
  /// - Idempotent within a single process via [_bootstrap] completer.
  /// - Emits a one-line "first-run setup" notice on [noticeSink] when the
  ///   bundle is missing or empty, then streams `bundle install` output to
  ///   the same sink so the user sees progress (not a silent hang).
  /// - No-ops on subsequent invocations.
  /// - Errors propagate so the caller can decide whether to abort the lane.
  Future<void> ensureBundleReady({StringSink? noticeSink}) {
    final existing = _bootstrap;
    if (existing != null) {
      return existing.future;
    }
    final completer = Completer<void>();
    _bootstrap = completer;

    Future<void>(() async {
      await _ensureBundleReadyImpl(noticeSink: noticeSink ?? stderr);
    }).then(completer.complete).catchError((Object error, StackTrace stack) {
      completer.completeError(error, stack);
    });

    return completer.future;
  }

  Future<void> _ensureBundleReadyImpl({required StringSink noticeSink}) async {
    final cachePath = _resolvedBundleCache.resolvePath();
    if (_bundleSeemsInstalled(cachePath)) {
      return;
    }

    final runnerDir = await _runnerResolver.resolve();
    final gemfilePath = p.join(runnerDir, 'Gemfile');
    if (!File(gemfilePath).existsSync()) {
      // Nothing we can do without a Gemfile — leave to the lane to fail loudly.
      return;
    }

    noticeSink.writeln(
      'fastlane_cli: first-run setup — installing gems into $cachePath …',
    );
    Directory(cachePath).createSync(recursive: true);

    await _processRunner.runStreaming(
      'bundle',
      <String>['install', '--path', cachePath, '--gemfile', gemfilePath],
      workingDirectory: runnerDir,
      onLog: (line, {required bool isError}) {
        noticeSink.writeln(line);
      },
    );
  }

  // ----- Individual checks ---------------------------------------------------

  Future<DoctorEntry> _checkFastlane() async {
    try {
      final result = await _processRunner.run('fastlane', <String>['--version']);
      if (result.exitCode != 0) {
        return DoctorEntry(
          status: DoctorStatus.error,
          name: 'fastlane',
          detail:
              'exited ${result.exitCode}; install fastlane via `brew install fastlane` (or your toolchain).',
        );
      }
      final version = _extractFastlaneVersion(result.stdout) ??
          result.firstStdoutLine;
      return DoctorEntry(
        status: DoctorStatus.ok,
        name: 'fastlane',
        detail: version.isEmpty ? 'available' : version,
      );
    } on ProcessNotFoundException {
      return const DoctorEntry(
        status: DoctorStatus.error,
        name: 'fastlane',
        detail: 'not found; install fastlane via `brew install fastlane` (or your toolchain).',
      );
    }
  }

  Future<DoctorEntry> _checkRuby() async {
    try {
      final result = await _processRunner.run('ruby', <String>['--version']);
      if (result.exitCode != 0) {
        return const DoctorEntry(
          status: DoctorStatus.error,
          name: 'ruby',
          detail:
              'ruby invocation failed; install Ruby 3.2+ via rbenv/asdf/homebrew.',
        );
      }
      final raw = result.firstStdoutLine;
      final version = _extractRubyVersion(raw);
      if (version == null) {
        return DoctorEntry(
          status: DoctorStatus.warning,
          name: 'ruby',
          detail: 'unrecognized output: $raw',
        );
      }
      if (!_isRubyAtLeast(version, 3, 2)) {
        return DoctorEntry(
          status: DoctorStatus.error,
          name: 'ruby',
          detail:
              'found $version; need >= 3.2 (use rbenv/asdf to install a newer Ruby).',
        );
      }
      return DoctorEntry(
        status: DoctorStatus.ok,
        name: 'ruby',
        detail: version,
      );
    } on ProcessNotFoundException {
      return const DoctorEntry(
        status: DoctorStatus.error,
        name: 'ruby',
        detail: 'ruby not found; install Ruby 3.2+ via rbenv/asdf/homebrew.',
      );
    }
  }

  Future<DoctorEntry> _checkBundleCache() async {
    final String cachePath;
    try {
      cachePath = _resolvedBundleCache.resolvePath();
    } on Object catch (error) {
      return DoctorEntry(
        status: DoctorStatus.error,
        name: 'bundle cache',
        detail: 'could not resolve cache path: $error',
      );
    }

    final dir = Directory(cachePath);
    final lockExists =
        File(p.join(cachePath, 'Gemfile.lock')).existsSync() ||
            _hasNestedFile(cachePath, 'Gemfile.lock');
    final installed = dir.existsSync() && _gemCount(cachePath) > 0;

    if (!installed || !lockExists) {
      return DoctorEntry(
        status: DoctorStatus.warning,
        name: 'bundle cache',
        detail:
            '$cachePath (empty — run `fastlane_cli doctor` once or any lane to bootstrap).',
      );
    }
    final gems = _gemCount(cachePath);
    return DoctorEntry(
      status: DoctorStatus.ok,
      name: 'bundle cache',
      detail: '$cachePath ($gems gems)',
    );
  }

  DoctorEntry _checkAppRoot(CliProfile profile) {
    final path = profile.appRootPath;
    if (!Directory(path).existsSync()) {
      return DoctorEntry(
        status: DoctorStatus.error,
        name: 'app root',
        detail: '$path (does not exist).',
      );
    }
    return DoctorEntry(
      status: DoctorStatus.ok,
      name: 'app root',
      detail: path,
    );
  }

  DoctorEntry _checkFastlaneDir(CliProfile profile) {
    final path = profile.fastlaneDirectoryPath;
    if (!Directory(path).existsSync()) {
      return DoctorEntry(
        status: DoctorStatus.warning,
        name: 'fastlane dir',
        detail: '$path (not found — lanes may fail).',
      );
    }
    return DoctorEntry(
      status: DoctorStatus.ok,
      name: 'fastlane dir',
      detail: path,
    );
  }

  DoctorEntry _checkIosCredentials() {
    final hasJsonKey = _envSet('APP_STORE_CONNECT_API_KEY_JSON_PATH');
    final hasP8Triplet = _envSet('APP_STORE_CONNECT_API_KEY_ID') &&
        _envSet('APP_STORE_CONNECT_API_KEY_ISSUER_ID') &&
        _envSet('APP_STORE_CONNECT_API_KEY_FILEPATH');
    if (hasJsonKey || hasP8Triplet) {
      return DoctorEntry(
        status: DoctorStatus.ok,
        name: 'iOS credentials',
        detail: hasJsonKey
            ? 'APP_STORE_CONNECT_API_KEY_JSON_PATH set'
            : 'APP_STORE_CONNECT_API_KEY_ID/_ISSUER_ID/_FILEPATH set',
      );
    }
    return const DoctorEntry(
      status: DoctorStatus.warning,
      name: 'iOS credentials',
      detail:
          'APP_STORE_CONNECT_API_KEY_JSON_PATH not set (or _ID/_ISSUER_ID/_FILEPATH triplet).',
    );
  }

  DoctorEntry _checkIosIdentifier() {
    const keys = <String>[
      'IOS_APP_IDENTIFIER',
      'FASTLANE_IOS_APP_IDENTIFIER',
      'FASTLANE_APP_IDENTIFIER',
      'APP_IDENTIFIER',
    ];
    final hit = keys.firstWhere(_envSet, orElse: () => '');
    if (hit.isEmpty) {
      return const DoctorEntry(
        status: DoctorStatus.warning,
        name: 'iOS bundle id',
        detail:
            'none of IOS_APP_IDENTIFIER / FASTLANE_IOS_APP_IDENTIFIER / FASTLANE_APP_IDENTIFIER / APP_IDENTIFIER set.',
      );
    }
    return DoctorEntry(
      status: DoctorStatus.ok,
      name: 'iOS bundle id',
      detail: '$hit set',
    );
  }

  DoctorEntry _checkAndroidCredentials() {
    if (_envSet('GOOGLE_PLAY_JSON_KEY_PATH')) {
      return const DoctorEntry(
        status: DoctorStatus.ok,
        name: 'Android credentials',
        detail: 'GOOGLE_PLAY_JSON_KEY_PATH set',
      );
    }
    return const DoctorEntry(
      status: DoctorStatus.warning,
      name: 'Android credentials',
      detail: 'GOOGLE_PLAY_JSON_KEY_PATH not set.',
    );
  }

  DoctorEntry _checkAndroidIdentifier() {
    const keys = <String>[
      'ANDROID_PACKAGE_NAME',
      'FASTLANE_ANDROID_APP_IDENTIFIER',
      'FASTLANE_APP_IDENTIFIER',
      'APP_IDENTIFIER',
    ];
    final hit = keys.firstWhere(_envSet, orElse: () => '');
    if (hit.isEmpty) {
      return const DoctorEntry(
        status: DoctorStatus.warning,
        name: 'Android package',
        detail:
            'none of ANDROID_PACKAGE_NAME / FASTLANE_ANDROID_APP_IDENTIFIER / FASTLANE_APP_IDENTIFIER / APP_IDENTIFIER set.',
      );
    }
    return DoctorEntry(
      status: DoctorStatus.ok,
      name: 'Android package',
      detail: '$hit set',
    );
  }

  // ----- Helpers -------------------------------------------------------------

  bool _envSet(String key) {
    final value = _environment[key];
    return value != null && value.trim().isNotEmpty;
  }

  Set<_Platform> _inferPlatforms(CliProfile profile) {
    final platforms = <_Platform>{};
    for (final action in profile.actions) {
      if (action.id.startsWith('ios_')) {
        platforms.add(_Platform.ios);
      } else if (action.id.startsWith('android_')) {
        platforms.add(_Platform.android);
      } else {
        // Fall back to the command's platform field, if present.
        final platform = action.command.platform?.toLowerCase().trim();
        if (platform == 'ios') {
          platforms.add(_Platform.ios);
        } else if (platform == 'android') {
          platforms.add(_Platform.android);
        }
      }
    }
    return platforms;
  }

  /// "fastlane 2.226.0" → "2.226.0". Falls back to null when unrecognized.
  String? _extractFastlaneVersion(String stdout) {
    final match =
        RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(stdout);
    return match?.group(1);
  }

  /// "ruby 3.2.4 (...)" → "3.2.4".
  String? _extractRubyVersion(String stdout) {
    final match =
        RegExp(r'ruby\s+(\d+\.\d+(?:\.\d+)?)').firstMatch(stdout);
    if (match != null) {
      return match.group(1);
    }
    final loose = RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(stdout);
    return loose?.group(1);
  }

  bool _isRubyAtLeast(String version, int major, int minor) {
    final parts = version.split('.');
    if (parts.length < 2) {
      return false;
    }
    final maj = int.tryParse(parts[0]) ?? 0;
    final min = int.tryParse(parts[1]) ?? 0;
    if (maj > major) return true;
    if (maj < major) return false;
    return min >= minor;
  }

  /// Considers the bundle "seemingly installed" when the cache dir exists and
  /// contains at least one `*.gemspec` or `cache/*.gem` artifact. Cheaper than
  /// re-running `bundle check` on every lane spawn.
  bool _bundleSeemsInstalled(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return false;
    }
    return _gemCount(path) > 0;
  }

  int _gemCount(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return 0;
    }
    try {
      // Bundle layout: <cachePath>/ruby/<abi>/gems/<gem-version>/...
      // We walk up to a couple of levels and count `gems/` children.
      final candidates = <Directory>[];
      void collect(Directory d, int depth) {
        if (depth > 4) return;
        for (final entity in d.listSync(followLinks: false)) {
          if (entity is Directory) {
            if (p.basename(entity.path) == 'gems') {
              candidates.add(entity);
            } else {
              collect(entity, depth + 1);
            }
          }
        }
      }

      collect(dir, 0);
      var count = 0;
      for (final gemsDir in candidates) {
        count += gemsDir
            .listSync(followLinks: false)
            .whereType<Directory>()
            .length;
      }
      return count;
    } on FileSystemException {
      return 0;
    }
  }

  bool _hasNestedFile(String root, String fileName) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      return false;
    }
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File && p.basename(entity.path) == fileName) {
          return true;
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }
}

enum _Platform { ios, android }
