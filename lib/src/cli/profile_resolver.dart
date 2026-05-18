import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the active `cli_profile.yaml` path using a fixed precedence:
///
/// 1. Explicit `--profile <path>` flag (passed in via [explicit]).
/// 2. `$FASTLANE_CLI_PROFILE` environment variable.
/// 3. `./cli_profile.yaml` in the current working directory.
///
/// If none resolve to an existing file, throws [ProfileResolutionException]
/// with a remediation message listing all three sources.
class ProfileResolver {
  const ProfileResolver({
    Map<String, String>? environment,
    Directory? workingDirectory,
  }) : _envOverride = environment,
       _cwdOverride = workingDirectory;

  final Map<String, String>? _envOverride;
  final Directory? _cwdOverride;

  Map<String, String> get _env => _envOverride ?? Platform.environment;
  Directory get _cwd => _cwdOverride ?? Directory.current;

  /// Returns an absolute path to the resolved `cli_profile.yaml`.
  String resolve({String? explicit}) {
    final attempts = <String>[];

    final fromFlag = _normalize(explicit);
    if (fromFlag != null) {
      attempts.add('--profile $fromFlag');
      if (File(fromFlag).existsSync()) {
        return fromFlag;
      }
      // An explicit flag that doesn't exist is a hard error — fall through to
      // the aggregate error so the user sees all three options.
    }

    final fromEnv = _normalize(_env['FASTLANE_CLI_PROFILE']);
    if (fromEnv != null) {
      attempts.add(r'$FASTLANE_CLI_PROFILE='
          '$fromEnv');
      if (File(fromEnv).existsSync()) {
        return fromEnv;
      }
    }

    final fromCwd = p.normalize(p.join(_cwd.path, 'cli_profile.yaml'));
    attempts.add('./cli_profile.yaml ($fromCwd)');
    if (File(fromCwd).existsSync()) {
      return fromCwd;
    }

    throw ProfileResolutionException(attempts: attempts);
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

class ProfileResolutionException implements Exception {
  ProfileResolutionException({required this.attempts});

  final List<String> attempts;

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('Could not locate cli_profile.yaml.')
      ..writeln('Tried (in order):');
    for (final attempt in attempts) {
      buf.writeln('  • $attempt');
    }
    buf.writeln(
      'Fix one of the following:\n'
      '  1. Pass --profile <path> on the command line.\n'
      r'  2. Export $FASTLANE_CLI_PROFILE to an absolute path.'
      '\n'
      '  3. Run from a directory containing cli_profile.yaml.',
    );
    return buf.toString();
  }
}
