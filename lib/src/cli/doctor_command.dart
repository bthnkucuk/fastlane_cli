import 'dart:io';

import 'package:args/command_runner.dart';

import '../model/cli_profile.dart';
import '../services/doctor_service.dart';
import '../services/profile_loader.dart';
import 'profile_resolver.dart';

/// `fastlane_cli doctor` — environment health check.
///
/// Thin shell over [DoctorService]: resolves the profile (best-effort — a
/// missing profile is non-fatal because the credential block is the only
/// part that needs it), runs the full sweep, prints a coloured report, and
/// exits 0/1 based on errors.
class DoctorCommand extends Command<int> {
  DoctorCommand({
    ProfileLoader? profileLoader,
    ProfileResolver? profileResolver,
    DoctorService? doctorService,
    StringSink? stdoutSink,
    StringSink? stderrSink,
    bool? useColor,
  }) : _profileLoader = profileLoader ?? const ProfileLoader(),
       _profileResolver = profileResolver ?? const ProfileResolver(),
       _doctorService = doctorService ?? DoctorService(),
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr,
       _useColor = useColor ?? stdout.supportsAnsiEscapes {
    argParser.addOption(
      'profile',
      abbr: 'p',
      help: 'Path to cli_profile.yaml',
    );
  }

  final ProfileLoader _profileLoader;
  final ProfileResolver _profileResolver;
  final DoctorService _doctorService;
  final StringSink _stdout;
  final StringSink _stderr;
  final bool _useColor;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Environment check (Ruby/Fastlane/bundle/credentials).';

  @override
  Future<int> run() async {
    final results = argResults!;

    CliProfile? profile;
    try {
      final profilePath = _profileResolver.resolve(
        explicit: results.option('profile'),
      );
      profile = await _profileLoader.load(profilePath);
    } on ProfileResolutionException catch (_) {
      // No profile available — proceed without the credential block.
      profile = null;
    } on FormatException catch (error) {
      // Profile present but malformed — surface a hint, continue without it.
      _stderr.writeln('Warning: could not load profile (${error.message}).');
      profile = null;
    }

    final report = await _doctorService.runFull(profile: profile);
    _printReport(report, profile: profile);

    return report.hasErrors ? 1 : 0;
  }

  void _printReport(DoctorReport report, {CliProfile? profile}) {
    final header = profile == null
        ? 'fastlane_cli doctor'
        : 'fastlane_cli doctor — ${profile.appName}';
    _stdout.writeln(header);

    final nameWidth = report.entries.isEmpty
        ? 0
        : report.entries
            .map((e) => e.name.length)
            .reduce((a, b) => a > b ? a : b);

    // Widest glyph label is "[WARN]" / "[FAIL]" = 6 chars (uncoloured).
    const glyphWidth = 6;
    for (final entry in report.entries) {
      final paddedName = entry.name.padRight(nameWidth);
      final rawLabel = _rawLabel(entry.status);
      final padding = ' ' * (glyphWidth - rawLabel.length);
      _stdout.writeln(
        '  ${_glyph(entry.status)}$padding $paddedName  ${entry.detail}',
      );
    }

    _stdout.writeln('');
    _stdout.writeln(
      '${report.okCount} OK · ${report.warningCount} warnings · ${report.errorCount} errors',
    );

    if (report.hasErrors) {
      _stdout.writeln('Doctor failed — fix the errors above and re-run.');
    } else if (report.warningCount > 0) {
      _stdout.writeln('Doctor passed (warnings only).');
    } else {
      _stdout.writeln('Doctor passed.');
    }
  }

  String _glyph(DoctorStatus status) {
    return switch (status) {
      DoctorStatus.ok => _colorize('[OK]', _ansiGreen),
      DoctorStatus.warning => _colorize('[WARN]', _ansiYellow),
      DoctorStatus.error => _colorize('[FAIL]', _ansiRed),
    };
  }

  String _rawLabel(DoctorStatus status) {
    return switch (status) {
      DoctorStatus.ok => '[OK]',
      DoctorStatus.warning => '[WARN]',
      DoctorStatus.error => '[FAIL]',
    };
  }

  String _colorize(String text, String color) {
    if (!_useColor) return text;
    return '$color$text$_ansiReset';
  }

  static const String _ansiReset = '[0m';
  static const String _ansiRed = '[31m';
  static const String _ansiGreen = '[32m';
  static const String _ansiYellow = '[33m';
}
