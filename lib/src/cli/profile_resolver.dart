import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the active `profile.yaml` path using a fixed precedence:
///
/// 1. Explicit `--profile <path>` flag (passed in via [explicit]). May be:
///    - a path to a `profile.yaml` file (legacy behaviour), or
///    - a path to a directory — we look inside it for `profile.yaml`
///      and then `fastlane/profile.yaml`. First hit wins.
/// 2. `$FASTLANE_CLI_PROFILE` environment variable (same file-or-dir
///    semantics as #1).
/// 3. Walk-up app discovery: from the current working directory, walk
///    up at most 8 levels looking for the first dir containing **both**
///    `pubspec.yaml` and `fastlane/profile.yaml`. If found, use that
///    `fastlane/profile.yaml`.
/// 4. `./profile.yaml` in the current working directory (legacy
///    final fallback).
///
/// At every step the legacy file name `cli_profile.yaml` is accepted as a
/// **deprecated** fallback: when `profile.yaml` is absent but the legacy file
/// exists, the legacy file is used and a one-line deprecation warning is
/// emitted on stderr exactly once per process.
///
/// If none resolve to an existing file, throws [ProfileResolutionException]
/// with a remediation message listing all four sources.
///
/// When the profile is discovered via #1-dir, #2-dir, or #3 (i.e. the user
/// did NOT explicitly point at a `.yaml` file), the resolver emits a single
/// line on [discoverySink] (default [stderr]): `discovered: <abs path>`.
/// Values are never logged — only the path itself.
class ProfileResolver {
  const ProfileResolver({
    Map<String, String>? environment,
    Directory? workingDirectory,
    StringSink? discoverySink,
    int walkUpMaxLevels = 8,
  }) : _envOverride = environment,
       _cwdOverride = workingDirectory,
       _discoverySinkOverride = discoverySink,
       _walkUpMaxLevels = walkUpMaxLevels;

  /// Primary per-app profile file name.
  static const String profileFileName = 'profile.yaml';

  /// Deprecated legacy per-app profile file name. Still resolved as a
  /// fallback, but triggers a one-time stderr deprecation warning.
  static const String legacyProfileFileName = 'cli_profile.yaml';

  final Map<String, String>? _envOverride;
  final Directory? _cwdOverride;
  final StringSink? _discoverySinkOverride;
  final int _walkUpMaxLevels;

  Map<String, String> get _env => _envOverride ?? Platform.environment;
  Directory get _cwd => _cwdOverride ?? Directory.current;
  StringSink get _discoverySink => _discoverySinkOverride ?? stderr;

  /// Returns an absolute path to the resolved `profile.yaml` (or the legacy
  /// `cli_profile.yaml`).
  String resolve({String? explicit}) {
    final attempts = <String>[];
    // Tracks whether the legacy-name deprecation warning has already fired,
    // so it is printed at most once per `resolve` call.
    final deprecationState = _DeprecationState();

    final fromFlag = _normalize(explicit);
    if (fromFlag != null) {
      attempts.add('--profile $fromFlag');
      final resolved = _resolvePathOrDir(fromFlag, deprecationState);
      if (resolved != null) {
        if (resolved != fromFlag) {
          _announceDiscovery(resolved);
        }
        return resolved;
      }
      // An explicit flag that doesn't resolve is a hard error — fall through
      // to the aggregate error so the user sees all sources.
    }

    final fromEnv = _normalize(_env['FASTLANE_CLI_PROFILE']);
    if (fromEnv != null) {
      attempts.add(r'$FASTLANE_CLI_PROFILE='
          '$fromEnv');
      final resolved = _resolvePathOrDir(fromEnv, deprecationState);
      if (resolved != null) {
        if (resolved != fromEnv) {
          _announceDiscovery(resolved);
        }
        return resolved;
      }
    }

    // Walk-up discovery: find the nearest Flutter app root by climbing the
    // cwd looking for `pubspec.yaml` + `fastlane/profile.yaml` (or the legacy
    // `fastlane/cli_profile.yaml`).
    final walkedUp = _walkUpForAppRoot(deprecationState);
    if (walkedUp != null) {
      attempts.add('walk-up app discovery: $walkedUp');
      _announceDiscovery(walkedUp);
      return walkedUp;
    } else {
      attempts.add(
        'walk-up app discovery (cwd: ${_cwd.path}, max $_walkUpMaxLevels levels)',
      );
    }

    final fromCwd = p.normalize(p.join(_cwd.path, profileFileName));
    attempts.add('./$profileFileName ($fromCwd)');
    if (File(fromCwd).existsSync()) {
      return fromCwd;
    }
    final legacyFromCwd = p.normalize(p.join(_cwd.path, legacyProfileFileName));
    if (File(legacyFromCwd).existsSync()) {
      _warnLegacy(deprecationState);
      return legacyFromCwd;
    }

    throw ProfileResolutionException(attempts: attempts);
  }

  /// Accepts either a file path or a directory path. For a directory, looks
  /// for `profile.yaml` then `fastlane/profile.yaml`, falling back to the
  /// legacy `cli_profile.yaml` names at each level. Returns the absolute file
  /// path on success, or `null` if nothing matched.
  String? _resolvePathOrDir(String absolutePath, _DeprecationState state) {
    final file = File(absolutePath);
    if (file.existsSync()) {
      if (p.basename(absolutePath) == legacyProfileFileName) {
        _warnLegacy(state);
      }
      return absolutePath;
    }
    final dir = Directory(absolutePath);
    if (!dir.existsSync()) {
      return null;
    }
    // Each candidate directory is checked for `profile.yaml` first, then the
    // legacy `cli_profile.yaml`, so a co-located primary file always wins.
    for (final baseDir in <String>[
      absolutePath,
      p.join(absolutePath, 'fastlane'),
    ]) {
      final primary = p.join(baseDir, profileFileName);
      if (File(primary).existsSync()) {
        return p.normalize(primary);
      }
      final legacy = p.join(baseDir, legacyProfileFileName);
      if (File(legacy).existsSync()) {
        _warnLegacy(state);
        return p.normalize(legacy);
      }
    }
    return null;
  }

  /// Walks up from cwd looking for a dir containing both `pubspec.yaml`
  /// and `fastlane/profile.yaml` (or the legacy `fastlane/cli_profile.yaml`).
  /// Returns the path of the discovered profile file (absolute, normalised),
  /// or `null`.
  String? _walkUpForAppRoot(_DeprecationState state) {
    var current = Directory(p.absolute(_cwd.path));
    for (var level = 0; level <= _walkUpMaxLevels; level++) {
      final pubspec = File(p.join(current.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final profile = File(
          p.join(current.path, 'fastlane', profileFileName),
        );
        if (profile.existsSync()) {
          return p.normalize(profile.path);
        }
        final legacyProfile = File(
          p.join(current.path, 'fastlane', legacyProfileFileName),
        );
        if (legacyProfile.existsSync()) {
          _warnLegacy(state);
          return p.normalize(legacyProfile.path);
        }
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        return null;
      }
      current = parent;
    }
    return null;
  }

  void _warnLegacy(_DeprecationState state) {
    if (state.warned) {
      return;
    }
    state.warned = true;
    _discoverySink.writeln(
      '⚠️  cli_profile.yaml is deprecated — rename it to profile.yaml',
    );
  }

  void _announceDiscovery(String path) {
    // Single, structural line. Never echo profile contents.
    _discoverySink.writeln('discovered: $path');
  }

  String? _normalize(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return p.isAbsolute(trimmed)
        ? p.normalize(trimmed)
        : p.normalize(p.join(_cwd.path, trimmed));
  }
}

/// Mutable one-shot flag for the legacy-name deprecation warning.
class _DeprecationState {
  bool warned = false;
}

class ProfileResolutionException implements Exception {
  ProfileResolutionException({required this.attempts});

  final List<String> attempts;

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('Could not locate profile.yaml.')
      ..writeln('Tried (in order):');
    for (final attempt in attempts) {
      buf.writeln('  • $attempt');
    }
    buf.writeln(
      'Fix one of the following:\n'
      '  1. Pass --profile <path> on the command line (file or app dir).\n'
      r'  2. Export $FASTLANE_CLI_PROFILE to an absolute path.'
      '\n'
      '  3. Run from inside a Flutter app whose root contains pubspec.yaml\n'
      '     and fastlane/profile.yaml (walked up to 8 levels).\n'
      '  4. Run from a directory containing profile.yaml.',
    );
    return buf.toString();
  }
}
