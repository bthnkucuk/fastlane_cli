import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/cli_action.dart';
import '../model/cli_profile.dart';
import '../model/command_request.dart';
import 'bundle_cache.dart';
import 'env_file_loader.dart';

class CommandBuilder {
  const CommandBuilder({
    BundleCache? bundleCache,
    Map<String, String>? environment,
  }) : _bundleCache = bundleCache,
       _environmentOverride = environment;

  final BundleCache? _bundleCache;
  final Map<String, String>? _environmentOverride;

  BundleCache get _resolvedBundleCache =>
      _bundleCache ?? BundleCache.fromPlatform();

  Map<String, String> get _environment =>
      _environmentOverride ?? Platform.environment;

  CommandRequest build({
    required CliProfile profile,
    required CliAction action,
  }) {
    return switch (action.command.type) {
      ActionCommandType.fastlane => _buildFastlane(
        profile: profile,
        action: action,
      ),
      ActionCommandType.flutter => _buildFlutter(
        profile: profile,
        action: action,
      ),
      ActionCommandType.dart => _buildDart(profile: profile, action: action),
      ActionCommandType.custom => _buildCustom(
        profile: profile,
        action: action,
      ),
    };
  }

  CommandRequest _buildFastlane({
    required CliProfile profile,
    required CliAction action,
  }) {
    final command = action.command;
    final lane = command.lane;
    if (lane == null || lane.isEmpty) {
      throw FormatException('Fastlane action "${action.id}" requires lane.');
    }

    final runnerFastlaneDirectory = profile.fastlaneRunnerDirectoryPath;
    final gemfilePath = p.normalize(p.join(runnerFastlaneDirectory, 'Gemfile'));
    if (!File(gemfilePath).existsSync()) {
      throw FormatException(
        'Gemfile not found for action "${action.id}": $gemfilePath',
      );
    }
    final runnerWorkingDirectory = p.normalize(
      p.dirname(runnerFastlaneDirectory),
    );
    if (!Directory(runnerWorkingDirectory).existsSync()) {
      throw FormatException(
        'Fastlane runner directory not found for action "${action.id}": $runnerWorkingDirectory',
      );
    }

    final args = <String>['exec', 'fastlane'];
    final platform = command.platform;
    if (platform != null && platform.isNotEmpty) {
      args.add(platform);
    }
    args.add(lane);
    for (final entry in command.options.entries) {
      args.add('${entry.key}:${entry.value}');
    }

    final dotenvValues = _loadAppEnvFiles(
      fastlaneDirectoryPath: profile.fastlaneDirectoryPath,
      appRootPath: profile.appRootPath,
    );
    final bundlePath = _resolvedBundleCache.resolvePath();

    return CommandRequest(
      executable: 'bundle',
      arguments: args,
      workingDirectory: runnerWorkingDirectory,
      environment: <String, String>{
        ...dotenvValues,
        'BUNDLE_GEMFILE': gemfilePath,
        'BUNDLE_PATH': bundlePath,
        'FASTLANE_ROOT': profile.fastlaneDirectoryPath,
        'FASTLANE_APP_ROOT': profile.appRootPath,
        'FASTLANE_CLI_FASTLANE_PATH': runnerFastlaneDirectory,
      },
    );
  }

  CommandRequest _buildFlutter({
    required CliProfile profile,
    required CliAction action,
  }) {
    return CommandRequest(
      executable: 'fvm',
      arguments: <String>['flutter', ...action.command.arguments],
      workingDirectory: profile.appRootPath,
      environment: const <String, String>{},
    );
  }

  CommandRequest _buildDart({
    required CliProfile profile,
    required CliAction action,
  }) {
    return CommandRequest(
      executable: 'fvm',
      arguments: <String>['dart', ...action.command.arguments],
      workingDirectory: profile.appRootPath,
      environment: const <String, String>{},
    );
  }

  CommandRequest _buildCustom({
    required CliProfile profile,
    required CliAction action,
  }) {
    final executable = action.command.executable;
    if (executable == null || executable.trim().isEmpty) {
      throw FormatException(
        'Custom action "${action.id}" requires executable.',
      );
    }
    return CommandRequest(
      executable: executable,
      arguments: action.command.arguments,
      workingDirectory: profile.appRootPath,
      environment: const <String, String>{},
    );
  }

  /// Discover and merge the app-side `.env` files for a fastlane child.
  ///
  /// Precedence (lowest → highest, i.e. later wins among files):
  ///   1. `<app-root>/.env`
  ///   2. `<app-fastlane-dir>/.env`
  ///   3. `<app-fastlane-dir>/.env.<FASTLANE_FLAVOR>` (only when set)
  ///
  /// The live shell environment always overrides the files — a value the
  /// user has explicitly exported must not be silently dropped. See
  /// [loadEnvFiles] for the parser contract.
  Map<String, String> _loadAppEnvFiles({
    required String fastlaneDirectoryPath,
    required String appRootPath,
  }) {
    final files = <File>[
      File(p.join(appRootPath, '.env')),
      File(p.join(fastlaneDirectoryPath, '.env')),
    ];
    final flavor = _environment['FASTLANE_FLAVOR']?.trim();
    if (flavor != null && flavor.isNotEmpty) {
      files.add(File(p.join(fastlaneDirectoryPath, '.env.$flavor')));
    }
    return loadEnvFiles(files, _environment);
  }
}
