import 'dart:io';

import 'package:args/args.dart';
import 'package:nocterm/nocterm.dart';
import 'package:zenrouter_nocterm/zenrouter_nocterm.dart';

import '../localization/locale_code.dart';
import '../routing/coordinator.dart';
import '../routing/environment.dart';
import '../services/command_builder.dart';
import '../services/command_execution_service.dart';
import '../services/guide_registry.dart';
import '../services/preflight_validator.dart';
import '../services/profile_loader.dart';

class FastlaneCliLauncher {
  FastlaneCliLauncher({ProfileLoader? profileLoader})
    : profileLoader = profileLoader ?? const ProfileLoader();

  final ProfileLoader profileLoader;

  Future<int> run(List<String> arguments) async {
    final parser = ArgParser()
      ..addOption('profile', abbr: 'p', help: 'Path to cli_profile.yaml')
      ..addOption(
        'lang',
        allowed: const <String>['tr', 'en'],
        help: 'Language override',
      )
      ..addFlag(
        'dry-run',
        defaultsTo: false,
        negatable: false,
        help: 'Build command and stream logs without execution',
      )
      ..addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

    try {
      final result = parser.parse(arguments);
      if (result.flag('help')) {
        stdout.writeln(
          'Usage: fastlane_cli --profile <path> [--lang tr|en] [--dry-run]',
        );
        stdout.writeln(parser.usage);
        return 0;
      }

      final profilePath = result.option('profile');
      if (profilePath == null || profilePath.trim().isEmpty) {
        stderr.writeln('Missing --profile option.');
        stderr.writeln(parser.usage);
        return 64;
      }

      final profile = await profileLoader.load(profilePath);
      final locale = LocaleCode.parse(
        result.option('lang'),
        fallback: profile.defaultLocale,
      );

      final environment = FastlaneCliEnvironment(
        profile: profile,
        initialLocale: locale,
        dryRun: result.flag('dry-run'),
        commandBuilder: const CommandBuilder(),
        executionService: const ProcessCommandExecutionService(),
        preflightValidator: const PreflightValidator(),
        guideRegistry: const GuideRegistry(),
      );
      final coordinator = FastlaneCliCoordinator(environment: environment);

      await runApp(
        NoctermApp(
          title: '${profile.appName} Fastlane CLI',
          theme: TuiThemeData.gruvboxDark,
          child: CoordinatorComponent(coordinator: coordinator),
        ),
      );

      return 0;
    } on ArgParserException catch (error) {
      stderr.writeln(error.message);
      return 64;
    } on FormatException catch (error) {
      stderr.writeln('Invalid input: ${error.message}');
      return 64;
    }
  }
}
