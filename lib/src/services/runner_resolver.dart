import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Resolves the absolute path of the bundled `fastlane/` runner directory.
///
/// Resolution order (first match wins):
///
/// 1. The supplied [profileOverride] (typically the `fastlane_runner_path`
///    field from `cli_profile.yaml`).
/// 2. The directory containing [Platform.resolvedExecutable]. We walk
///    upwards looking for either `share/fastlane_cli/fastlane/` (Homebrew
///    install layout) or `fastlane/` (source / `dart compile exe` layout).
/// 3. `package:fastlane_cli/_dummy.dart` resolved via [Isolate.resolvePackageUri],
///    then `..resolve('../fastlane/')`. Covers `dart run` from a checkout and
///    `dart pub global activate` installs.
/// 4. A [StateError] describing every path that was tried.
///
/// The resolver holds no global state — callers construct it directly. Tests
/// can substitute [executablePath] and [packageUriResolver] to simulate the
/// brew layout, an AOT binary, or a `pub global` install.
class RunnerResolver {
  const RunnerResolver({
    String Function()? executablePath,
    Future<Uri?> Function(Uri uri)? packageUriResolver,
  }) : _executablePath = executablePath ?? _defaultExecutablePath,
       _packageUriResolver = packageUriResolver ?? Isolate.resolvePackageUri;

  final String Function() _executablePath;
  final Future<Uri?> Function(Uri uri) _packageUriResolver;

  /// Maximum directory levels to climb from [Platform.resolvedExecutable]
  /// before giving up. Brew prefixes are normally 2 levels deep
  /// (`<prefix>/bin/fastlane_cli`); we allow a generous margin for unusual
  /// install layouts without scanning the whole filesystem.
  static const int _maxClimbLevels = 6;

  /// Returns the absolute path of the fastlane runner directory.
  ///
  /// Throws [StateError] with all attempted paths if no match is found.
  Future<String> resolve({String? profileOverride}) async {
    final attempted = <String>[];

    // (1) Profile override.
    final override = _normalizedOverride(profileOverride);
    if (override != null) {
      attempted.add('profile override: $override');
      if (_isFastlaneDir(override)) {
        return override;
      }
    }

    // (2) Walk up from Platform.resolvedExecutable.
    final fromExecutable = _resolveFromExecutable(attempted);
    if (fromExecutable != null) {
      return fromExecutable;
    }

    // (3) package:fastlane_cli/_dummy.dart → ../fastlane/.
    final fromPackage = await _resolveFromPackageUri(attempted);
    if (fromPackage != null) {
      return fromPackage;
    }

    // (4) Give up with a clear, structured error.
    throw StateError(
      'fastlane runner not found. Tried:\n'
      '${attempted.map((path) => '  - $path').join('\n')}\n'
      'Set `app.fastlane_runner_path` in cli_profile.yaml to override, or '
      'reinstall fastlane_cli so the bundled fastlane/ directory ships next '
      'to the binary.',
    );
  }

  String? _resolveFromExecutable(List<String> attempted) {
    final exePath = _executablePath();
    if (exePath.isEmpty) {
      return null;
    }
    var current = Directory(p.dirname(p.absolute(exePath)));

    for (var level = 0; level <= _maxClimbLevels; level++) {
      // Brew layout: <prefix>/share/fastlane_cli/fastlane/
      final brewCandidate = p.join(
        current.path,
        'share',
        'fastlane_cli',
        'fastlane',
      );
      attempted.add('executable walk: $brewCandidate');
      if (_isFastlaneDir(brewCandidate)) {
        return p.normalize(brewCandidate);
      }

      // Source / AOT layout: <repo>/fastlane/
      final sourceCandidate = p.join(current.path, 'fastlane');
      attempted.add('executable walk: $sourceCandidate');
      if (_isFastlaneDir(sourceCandidate)) {
        return p.normalize(sourceCandidate);
      }

      final parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
    return null;
  }

  Future<String?> _resolveFromPackageUri(List<String> attempted) async {
    try {
      final packageUri = await _packageUriResolver(
        Uri.parse('package:fastlane_cli/_dummy.dart'),
      );
      if (packageUri == null) {
        attempted.add('package uri: <unresolved>');
        return null;
      }
      final fastlaneUri = packageUri.resolve('../fastlane/');
      final candidate = p.normalize(p.fromUri(fastlaneUri));
      attempted.add('package uri: $candidate');
      if (_isFastlaneDir(candidate)) {
        return candidate;
      }
    } catch (error) {
      attempted.add('package uri: <error: $error>');
    }
    return null;
  }

  /// Treats a directory as the fastlane runner when it exists and contains a
  /// `Fastfile`. Empty/placeholder directories therefore do not satisfy
  /// resolution — this is intentional, since the runner is unusable without
  /// the Fastfile.
  bool _isFastlaneDir(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return false;
    }
    return File(p.join(path, 'Fastfile')).existsSync();
  }

  String? _normalizedOverride(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return p.normalize(p.absolute(trimmed));
  }

  static String _defaultExecutablePath() => Platform.resolvedExecutable;
}
