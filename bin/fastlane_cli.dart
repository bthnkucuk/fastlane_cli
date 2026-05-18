import 'dart:io';

import 'package:fastlane_cli/src/cli/fastlane_cli_runner.dart';

Future<void> main(List<String> arguments) async {
  final code = await FastlaneCliRunner().run(arguments);
  if (code != 0) {
    exitCode = code;
  }
}
