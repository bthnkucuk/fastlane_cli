import 'dart:io';

import 'package:args/command_runner.dart';

import '../services/profile_loader.dart';
import 'profile_resolver.dart';

/// `fastlane_cli completion <bash|zsh|fish>` — emit a shell completion script.
///
/// The script always covers the static subcommand list. When a profile is
/// discoverable (via the standard three-way resolution rule), action IDs are
/// added too so `fastlane_cli run <TAB>` completes them.
class CompletionCommand extends Command<int> {
  CompletionCommand({
    ProfileLoader? profileLoader,
    ProfileResolver? profileResolver,
    List<String>? subcommandNames,
    StringSink? stdoutSink,
    StringSink? stderrSink,
  }) : _profileLoader = profileLoader ?? const ProfileLoader(),
       _profileResolver = profileResolver ?? const ProfileResolver(),
       _explicitSubcommands = subcommandNames,
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr {
    argParser.addOption(
      'profile',
      abbr: 'p',
      help: 'Path to profile.yaml (optional — used to discover action ids).',
    );
  }

  static const List<String> defaultSubcommands = <String>[
    'run',
    'list',
    'doctor',
    'init',
    'skills',
    'completion',
    'help',
  ];

  final ProfileLoader _profileLoader;
  final ProfileResolver _profileResolver;
  final List<String>? _explicitSubcommands;
  final StringSink _stdout;
  final StringSink _stderr;

  @override
  String get name => 'completion';

  @override
  String get description =>
      'Print a shell completion script (bash, zsh, or fish).';

  @override
  String get invocation => 'fastlane_cli completion <bash|zsh|fish>';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.isEmpty) {
      _stderr.writeln('Missing required shell argument (bash|zsh|fish).');
      _stderr.writeln(usage);
      return 64;
    }
    final shell = results.rest.first.toLowerCase();
    if (!const <String>{'bash', 'zsh', 'fish'}.contains(shell)) {
      _stderr.writeln('Unsupported shell "$shell". Choose bash, zsh, or fish.');
      return 64;
    }

    final subcommands = _explicitSubcommands ?? defaultSubcommands;
    final actionIds = await _discoverActionIds(results.option('profile'));

    final script = switch (shell) {
      'bash' => _renderBash(subcommands, actionIds),
      'zsh' => _renderZsh(subcommands, actionIds),
      'fish' => _renderFish(subcommands, actionIds),
      _ => '',
    };
    _stdout.writeln(script);
    return 0;
  }

  Future<List<String>> _discoverActionIds(String? explicitProfile) async {
    try {
      final path = _profileResolver.resolve(explicit: explicitProfile);
      final profile = await _profileLoader.load(path);
      return profile.actions.map((a) => a.id).toList();
    } on ProfileResolutionException {
      return const <String>[];
    } catch (_) {
      // A malformed profile shouldn't break completion script emission.
      return const <String>[];
    }
  }

  String _renderBash(List<String> subs, List<String> actions) {
    final subList = subs.join(' ');
    final actionList = actions.join(' ');
    return '''# fastlane_cli bash completion
_fastlane_cli() {
  local cur prev
  COMPREPLY=()
  cur="\${COMP_WORDS[COMP_CWORD]}"
  prev="\${COMP_WORDS[COMP_CWORD-1]}"
  if [ "\$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( \$(compgen -W "$subList" -- "\$cur") )
    return 0
  fi
  case "\${COMP_WORDS[1]}" in
    run)
      COMPREPLY=( \$(compgen -W "$actionList" -- "\$cur") )
      ;;
    *) ;;
  esac
}
complete -F _fastlane_cli fastlane_cli
''';
  }

  String _renderZsh(List<String> subs, List<String> actions) {
    final subList = subs.map((s) => "'$s'").join(' ');
    final actionList = actions.map((a) => "'$a'").join(' ');
    return '''#compdef fastlane_cli
# fastlane_cli zsh completion
_fastlane_cli() {
  local -a subcommands actions
  subcommands=($subList)
  actions=($actionList)
  if (( CURRENT == 2 )); then
    _describe 'subcommand' subcommands
    return
  fi
  case \$words[2] in
    run)
      _describe 'action' actions
      ;;
  esac
}
compdef _fastlane_cli fastlane_cli
''';
  }

  String _renderFish(List<String> subs, List<String> actions) {
    final buf = StringBuffer('# fastlane_cli fish completion\n');
    for (final sub in subs) {
      buf.writeln(
        "complete -c fastlane_cli -n '__fish_use_subcommand' -a '$sub'",
      );
    }
    for (final id in actions) {
      buf.writeln(
        "complete -c fastlane_cli -n '__fish_seen_subcommand_from run' -a '$id'",
      );
    }
    return buf.toString();
  }
}
