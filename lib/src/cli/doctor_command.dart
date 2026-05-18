import 'dart:io';

import 'package:args/command_runner.dart';

import '../services/profile_loader.dart';
import 'profile_resolver.dart';

/// `fastlane_cli doctor` — shell wired in Track A2; real check logic lands in
/// Track B2 (`B2. doctor subcommand body`). For now this command verifies the
/// profile can be located so users get an early error before the real impl
/// arrives.
class DoctorCommand extends Command<int> {
  DoctorCommand({
    ProfileLoader? profileLoader,
    ProfileResolver? profileResolver,
    StringSink? stdoutSink,
    StringSink? stderrSink,
  }) : _profileLoader = profileLoader ?? const ProfileLoader(),
       _profileResolver = profileResolver ?? const ProfileResolver(),
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr {
    argParser.addOption(
      'profile',
      abbr: 'p',
      help: 'Path to cli_profile.yaml',
    );
  }

  final ProfileLoader _profileLoader;
  final ProfileResolver _profileResolver;
  final StringSink _stdout;
  final StringSink _stderr;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Environment check (Ruby/Fastlane/bundle/credentials).';

  @override
  Future<int> run() async {
    final results = argResults!;
    final String profilePath;
    try {
      profilePath = _profileResolver.resolve(
        explicit: results.option('profile'),
      );
    } on ProfileResolutionException catch (error) {
      _stderr.writeln(error.toString());
      return 66;
    }

    // Touch the loader so a malformed profile shows up here too.
    await _profileLoader.load(profilePath);

    _stdout.writeln('Profile: $profilePath');
    _stdout.writeln('TODO: doctor implementation lands in Track B2');
    return 0;
  }
}
