import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/cli_action.dart';
import '../model/cli_profile.dart';
import '../model/command_request.dart';
import 'bundle_cache.dart';

class CommandBuilder {
  const CommandBuilder({BundleCache? bundleCache}) : _bundleCache = bundleCache;

  final BundleCache? _bundleCache;

  BundleCache get _resolvedBundleCache =>
      _bundleCache ?? BundleCache.fromPlatform();

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

    final dotenvValues = _readDotEnv(profile.fastlaneDirectoryPath);
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

  Map<String, String> _readDotEnv(String fastlaneDirectoryPath) {
    final envFile = File(p.join(fastlaneDirectoryPath, '.env'));
    if (!envFile.existsSync()) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    for (final rawLine in envFile.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }

      final key = line.substring(0, separator).trim();
      if (key.isEmpty) {
        continue;
      }
      var value = line.substring(separator + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      result[key] = value;
    }
    return result;
  }
}
