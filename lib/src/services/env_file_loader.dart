import 'dart:io';

/// Pure-function `.env` parser + multi-file merger used by `CommandBuilder`
/// to forward an app's `.env` values into the spawned `bundle exec fastlane`
/// child process.
///
/// Contract:
/// - [loadEnvFiles] takes a list of [File]s in **ascending precedence order**
///   (file at index 0 is the weakest, file at index N-1 is the strongest among
///   files), plus the live shell environment [shellEnv] which always wins.
///   Keys already present in `shellEnv` are never overwritten.
/// - Missing files are silently skipped — callers don't have to pre-filter.
/// - Returns a fresh [Map] ready to drop into `Process.start`'s
///   `environment:` parameter.
///
/// Parser rules (intentionally narrow):
/// - `key=value` per line.
/// - Lines starting with `#` are comments.
/// - Blank lines ignored.
/// - Optional `export` prefix tolerated: `export KEY=value`.
/// - Single- or double-quoted values are stripped (`KEY="value"` → `value`).
/// - `${OTHER_KEY}` interpolation is **NOT supported** — if a value contains
///   `${...}` literally, it is passed through unchanged. (We may add
///   interpolation later; tracked nowhere yet.)
/// - Multi-line values are not supported.
/// - A malformed line emits a one-line warning to [warningSink] (default
///   [stderr]) and is skipped; we never abort the entire load on a single
///   bad line.
///
/// Secret-safety: the loader **never** echoes values to any sink. The
/// warning is structural (the file path and line number, never the value)
/// so a leaked secret in a malformed line still does not reach the log.
Map<String, String> loadEnvFiles(
  List<File> files,
  Map<String, String> shellEnv, {
  StringSink? warningSink,
}) {
  final sink = warningSink ?? stderr;
  final merged = <String, String>{};

  for (final file in files) {
    if (!file.existsSync()) {
      continue;
    }
    final parsed = _parseEnvFile(file, warningSink: sink);
    // Later files override earlier ones (precedence-ascending input).
    merged.addAll(parsed);
  }

  // Shell env is the strongest layer — never overwrite a key the caller
  // already exported. We DO want shell-only keys forwarded so the child
  // sees the same view the user has, but `CommandBuilder` only forwards
  // the dotenv overlay (plus the bundle/fastlane plumbing it adds
  // itself); `Process.start` will inherit the shell environment by
  // default for any key we omit.
  for (final entry in shellEnv.entries) {
    if (merged.containsKey(entry.key)) {
      merged[entry.key] = entry.value;
    }
  }

  return merged;
}

Map<String, String> _parseEnvFile(
  File file, {
  required StringSink warningSink,
}) {
  final result = <String, String>{};
  List<String> lines;
  try {
    lines = file.readAsLinesSync();
  } on FileSystemException catch (error) {
    warningSink.writeln(
      'fastlane_cli: could not read env file ${file.path}: ${error.message}',
    );
    return result;
  }

  for (var i = 0; i < lines.length; i++) {
    final rawLine = lines[i];
    final lineNumber = i + 1;
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    // Strip optional `export ` prefix.
    var body = trimmed;
    if (body.startsWith('export ')) {
      body = body.substring('export '.length).trimLeft();
    }

    final separator = body.indexOf('=');
    if (separator <= 0) {
      // No `=`, or starts with `=` → not a valid assignment.
      warningSink.writeln(
        'fastlane_cli: malformed env line at ${file.path}:$lineNumber (skipped).',
      );
      continue;
    }

    final key = body.substring(0, separator).trim();
    if (key.isEmpty || !_isValidEnvKey(key)) {
      warningSink.writeln(
        'fastlane_cli: malformed env line at ${file.path}:$lineNumber (skipped).',
      );
      continue;
    }

    var value = body.substring(separator + 1).trim();
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        value = value.substring(1, value.length - 1);
      }
    }
    // Note: `${VAR}` interpolation is NOT performed — see header comment.
    result[key] = value;
  }
  return result;
}

bool _isValidEnvKey(String key) {
  // POSIX-ish env names: letters, digits, underscore; can't start with digit.
  if (key.isEmpty) return false;
  final first = key.codeUnitAt(0);
  final isLetterOrUnderscore = (first >= 0x41 && first <= 0x5A) ||
      (first >= 0x61 && first <= 0x7A) ||
      first == 0x5F;
  if (!isLetterOrUnderscore) return false;
  for (var i = 1; i < key.length; i++) {
    final c = key.codeUnitAt(i);
    final isWordChar = (c >= 0x41 && c <= 0x5A) ||
        (c >= 0x61 && c <= 0x7A) ||
        (c >= 0x30 && c <= 0x39) ||
        c == 0x5F;
    if (!isWordChar) return false;
  }
  return true;
}
