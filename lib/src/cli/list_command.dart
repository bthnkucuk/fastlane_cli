import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../services/profile_loader.dart';
import 'profile_resolver.dart';

/// `fastlane_cli list [--category <id>] [--json]` — enumerate actions.
class ListCommand extends Command<int> {
  ListCommand({
    ProfileLoader? profileLoader,
    ProfileResolver? profileResolver,
    StringSink? stdoutSink,
    StringSink? stderrSink,
  }) : _profileLoader = profileLoader ?? const ProfileLoader(),
       _profileResolver = profileResolver ?? const ProfileResolver(),
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr {
    argParser
      ..addOption(
        'profile',
        abbr: 'p',
        help: 'Path to profile.yaml',
      )
      ..addOption(
        'category',
        abbr: 'c',
        help: 'Filter to a single category id.',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        negatable: false,
        help: 'Emit JSON instead of plain text.',
      );
  }

  final ProfileLoader _profileLoader;
  final ProfileResolver _profileResolver;
  final StringSink _stdout;
  final StringSink _stderr;

  @override
  String get name => 'list';

  @override
  String get description =>
      'Enumerate actions defined in the active profile.';

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

    final profile = await _profileLoader.load(profilePath);
    final category = results.option('category');
    final locale = profile.defaultLocale;

    final actions = category == null
        ? profile.actions
        : profile.actions.where((a) => a.categoryId == category).toList();

    if (results.flag('json')) {
      final payload = <Map<String, Object?>>[
        for (final action in actions)
          <String, Object?>{
            'id': action.id,
            'title': action.titleFor(locale),
            'description': action.descriptionFor(locale),
            'category': action.categoryId,
          },
      ];
      _stdout.writeln(jsonEncode(payload));
      return 0;
    }

    if (actions.isEmpty) {
      _stdout.writeln(
        category == null
            ? 'No actions in profile.'
            : 'No actions in category "$category".',
      );
      return 0;
    }

    for (final action in actions) {
      _stdout.writeln(
        '${action.id}\t[${action.categoryId}]\t${action.titleFor(locale)}',
      );
      final desc = action.descriptionFor(locale);
      if (desc.isNotEmpty) {
        _stdout.writeln('    $desc');
      }
    }
    return 0;
  }
}
