import 'dart:io';

import 'package:args/args.dart';
import 'package:nocterm/nocterm.dart';
import 'package:zenrouter_nocterm/zenrouter_nocterm.dart';

import '../localization/parse_locale.dart';
import '../model/run_session.dart';
import '../routing/coordinator.dart';
import '../routing/environment.dart';
import '../routing/routes/run_route.dart';
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
      final locale = parseLocale(
        result.option('lang'),
        fallback: profile.defaultLocale,
      );

      final environment = FastlaneCliEnvironment(
        profile: profile,
        initialLocale: locale,
        dryRun: result.flag('dry-run'),
        commandBuilder: const CommandBuilder(),
        executionService: ProcessCommandExecutionService(),
        preflightValidator: const PreflightValidator(),
        guideRegistry: const GuideRegistry(),
      );
      final coordinator = FastlaneCliCoordinator(environment: environment);

      await runApp(
        _TitleUpdatingApp(
          baseTitle: '${profile.appName} Fastlane CLI',
          coordinator: coordinator,
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

/// Wraps [NoctermApp] so the OSC terminal-window title reflects the active
/// run tab. Subscribes to the coordinator's run-tabs path and to whichever
/// run-session controller is currently focused; rebuilds with an updated
/// `title:` whenever either changes. [NoctermApp.didUpdateComponent] picks
/// up the change and re-emits the OSC 0/2 escape sequence.
class _TitleUpdatingApp extends StatefulComponent {
  const _TitleUpdatingApp({
    required this.baseTitle,
    required this.coordinator,
  });

  final String baseTitle;
  final FastlaneCliCoordinator coordinator;

  @override
  State<_TitleUpdatingApp> createState() => _TitleUpdatingAppState();
}

class _TitleUpdatingAppState extends State<_TitleUpdatingApp> {
  Listenable? _trackedController;
  RunRoute? _trackedRoute;

  @override
  void initState() {
    super.initState();
    component.coordinator.runTabsPath.addListener(_onRunTabsChanged);
    _syncTrackedController();
  }

  @override
  void dispose() {
    component.coordinator.runTabsPath.removeListener(_onRunTabsChanged);
    _trackedController?.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onRunTabsChanged() {
    _syncTrackedController();
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _syncTrackedController() {
    final active = component.coordinator.runTabsPath.activeRoute;
    if (identical(active, _trackedRoute)) return;
    _trackedController?.removeListener(_onSessionChanged);
    _trackedRoute = active;
    _trackedController = active?.controller;
    _trackedController?.addListener(_onSessionChanged);
  }

  String _computeTitle() {
    final active = component.coordinator.runTabsPath.activeRoute;
    if (active == null) return component.baseTitle;
    final session = active.controller.session;
    final suffix = switch (session.status) {
      RunStatus.running || RunStatus.validating => ' (running)',
      RunStatus.failed => ' (failed)',
      RunStatus.succeeded => ' (done)',
      RunStatus.dryRun => ' (dry-run)',
      _ => '',
    };
    return '${component.baseTitle} — ${active.actionId}$suffix';
  }

  @override
  Component build(BuildContext context) {
    return NoctermApp(
      title: _computeTitle(),
      theme: TuiThemeData.gruvboxDark,
      child: CoordinatorComponent(coordinator: component.coordinator),
    );
  }
}
