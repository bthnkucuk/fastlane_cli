import 'dart:io';

import 'package:path/path.dart' as p;

/// Disposition for a single skill entry when planned / installed.
enum SkillAction {
  /// Source exists, no destination present yet → will be copied fresh.
  install,

  /// Destination already exists and `--force` is not set → leave alone.
  skip,

  /// Destination already exists and `--force` is set → overwrite.
  overwrite,

  /// I/O failure during the operation.
  error,
}

/// Single entry in an install plan.
class SkillEntry {
  const SkillEntry({
    required this.name,
    required this.sourcePath,
    required this.destinationPath,
    required this.action,
    this.errorMessage,
  });

  /// The skill's directory name (e.g. `fastlane-summary-log`) or `README.md`
  /// for the top-level index file.
  final String name;

  /// Absolute path to the source on disk.
  final String sourcePath;

  /// Absolute path to where it would land on disk.
  final String destinationPath;

  /// What will happen / happened.
  final SkillAction action;

  /// Populated when [action] is [SkillAction.error].
  final String? errorMessage;

  SkillEntry copyWith({SkillAction? action, String? errorMessage}) =>
      SkillEntry(
        name: name,
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        action: action ?? this.action,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

/// What an install would do — produced by [SkillsInstaller.plan] and consumed
/// by either `--dry-run` or [SkillsInstaller.install].
class InstallPlan {
  const InstallPlan({
    required this.source,
    required this.destination,
    required this.destinationLabel,
    required this.entries,
  });

  /// Absolute path of the bundled `skills/` directory.
  final String source;

  /// Absolute path of the target `.claude/skills/` directory.
  final String destination;

  /// Human label: `project` or `global`.
  final String destinationLabel;

  final List<SkillEntry> entries;
}

/// The realised outcome of [SkillsInstaller.install].
class InstallReport {
  const InstallReport({required this.plan, required this.entries});

  final InstallPlan plan;
  final List<SkillEntry> entries;

  int get installed =>
      entries.where((e) => e.action == SkillAction.install).length;
  int get skipped => entries.where((e) => e.action == SkillAction.skip).length;
  int get overwritten =>
      entries.where((e) => e.action == SkillAction.overwrite).length;
  int get errors => entries.where((e) => e.action == SkillAction.error).length;
}

/// Pure I/O service that copies the bundled `skills/` tree into a target
/// `.claude/skills/` directory.
///
/// Constructor injection only — no global state. `dart:io` is used directly,
/// matching the rest of `lib/src/services/` (no `FileSystem` abstraction).
class SkillsInstaller {
  const SkillsInstaller();

  /// Compute the plan without touching the destination.
  ///
  /// [sourceDir] must point at a directory containing skill subdirectories
  /// (and optionally a `README.md`). [destinationDir] is the target
  /// `.claude/skills/` directory and need not yet exist.
  InstallPlan plan({
    required String sourceDir,
    required String destinationDir,
    required String destinationLabel,
    bool force = false,
  }) {
    final source = Directory(sourceDir);
    if (!source.existsSync()) {
      throw StateError('Skills source directory does not exist: $sourceDir');
    }

    final entries = <SkillEntry>[];
    final children = source.listSync(followLinks: false)
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (final entity in children) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        entries.add(_planEntry(
          name: name,
          sourcePath: entity.path,
          destinationDir: destinationDir,
          force: force,
        ));
      } else if (entity is File && name == 'README.md') {
        entries.add(_planEntry(
          name: name,
          sourcePath: entity.path,
          destinationDir: destinationDir,
          force: force,
        ));
      }
      // Anything else (stray files, symlinks) is intentionally ignored — the
      // bundled tree only contains skill directories and an index README.
    }

    return InstallPlan(
      source: source.absolute.path,
      destination: p.absolute(destinationDir),
      destinationLabel: destinationLabel,
      entries: entries,
    );
  }

  SkillEntry _planEntry({
    required String name,
    required String sourcePath,
    required String destinationDir,
    required bool force,
  }) {
    final destinationPath = p.join(destinationDir, name);
    final exists = FileSystemEntity.typeSync(destinationPath) !=
        FileSystemEntityType.notFound;
    final SkillAction action;
    if (exists && !force) {
      action = SkillAction.skip;
    } else if (exists && force) {
      action = SkillAction.overwrite;
    } else {
      action = SkillAction.install;
    }
    return SkillEntry(
      name: name,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      action: action,
    );
  }

  /// Executes the [plan] against disk and returns the actual outcome.
  ///
  /// I/O failures on a single entry are caught and surfaced via
  /// [SkillAction.error] — the install carries on so a single bad entry does
  /// not abort the whole batch. Callers can map `report.errors > 0` to a
  /// non-zero exit code.
  Future<InstallReport> install(InstallPlan plan) async {
    Directory(plan.destination).createSync(recursive: true);

    final results = <SkillEntry>[];
    for (final entry in plan.entries) {
      try {
        switch (entry.action) {
          case SkillAction.skip:
            results.add(entry);
          case SkillAction.overwrite:
            _removeExisting(entry.destinationPath);
            _copyEntity(entry.sourcePath, entry.destinationPath);
            results.add(entry);
          case SkillAction.install:
            _copyEntity(entry.sourcePath, entry.destinationPath);
            results.add(entry);
          case SkillAction.error:
            // Pre-existing planning error — keep as-is.
            results.add(entry);
        }
      } catch (error) {
        results.add(entry.copyWith(
          action: SkillAction.error,
          errorMessage: error.toString(),
        ));
      }
    }

    return InstallReport(plan: plan, entries: results);
  }

  void _removeExisting(String path) {
    final type = FileSystemEntity.typeSync(path);
    switch (type) {
      case FileSystemEntityType.directory:
        Directory(path).deleteSync(recursive: true);
      case FileSystemEntityType.file:
      case FileSystemEntityType.link:
        File(path).deleteSync();
      case FileSystemEntityType.notFound:
        return;
      default:
        Directory(path).deleteSync(recursive: true);
    }
  }

  void _copyEntity(String source, String destination) {
    final type = FileSystemEntity.typeSync(source);
    switch (type) {
      case FileSystemEntityType.directory:
        _copyDirectory(Directory(source), Directory(destination));
      case FileSystemEntityType.file:
        Directory(p.dirname(destination)).createSync(recursive: true);
        File(source).copySync(destination);
      default:
        throw StateError('Unsupported source entity: $source ($type)');
    }
  }

  void _copyDirectory(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      final targetPath = p.join(destination.path, name);
      if (entity is Directory) {
        _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        entity.copySync(targetPath);
      }
      // Symlinks are intentionally skipped — the bundled tree never contains
      // any, and copying them blindly across machines is unsafe.
    }
  }
}
