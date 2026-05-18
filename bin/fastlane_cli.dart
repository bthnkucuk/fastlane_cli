import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';

Future<void> main(List<String> arguments) async {
  final launcher = FastlaneCliLauncher();
  final code = await launcher.run(arguments);
  if (code != 0) {
    exitCode = code;
  }
}
