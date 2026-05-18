import 'package:fastlane_cli/fastlane_cli.dart';

CliProfile createTestProfile({
  required String appRootPath,
  required List<CliAction> actions,
  required List<CliCategory> categories,
  List<String> shortcuts = const <String>[],
}) {
  return CliProfile(
    appName: 'TestApp',
    profilePath: '$appRootPath/cli_profile.yaml',
    appRootPath: appRootPath,
    fastlanePath: 'fastlane',
    fastlaneRunnerPath: 'fastlane',
    defaultLocale: LocaleCode.tr,
    supportedLocales: const <LocaleCode>[LocaleCode.tr, LocaleCode.en],
    categories: categories,
    actions: actions,
    shortcutActionIds: shortcuts,
  );
}

CliCategory makeCategory({
  required String id,
  required List<String> actionIds,
}) {
  return CliCategory(
    id: id,
    title: <LocaleCode, String>{
      LocaleCode.tr: id.toUpperCase(),
      LocaleCode.en: id.toUpperCase(),
    },
    description: <LocaleCode, String>{
      LocaleCode.tr: '$id category',
      LocaleCode.en: '$id category',
    },
    actionIds: actionIds,
  );
}

CliAction makeFastlaneAction({
  required String id,
  required String categoryId,
  required String lane,
  String? platform,
  bool shortcut = false,
  bool requiresConfirmation = false,
  bool requiresOverwriteConfirmation = false,
  List<PreflightCheck> preflightChecks = const <PreflightCheck>[],
}) {
  return CliAction(
    id: id,
    categoryId: categoryId,
    title: const <LocaleCode, String>{
      LocaleCode.tr: 'Aksiyon',
      LocaleCode.en: 'Action',
    },
    description: const <LocaleCode, String>{
      LocaleCode.tr: 'Açıklama',
      LocaleCode.en: 'Description',
    },
    command: CliActionCommand(
      type: ActionCommandType.fastlane,
      platform: platform,
      lane: lane,
      options: const <String, String>{},
    ),
    preflightChecks: preflightChecks,
    shortcut: shortcut,
    requiresConfirmation: requiresConfirmation,
    requiresOverwriteConfirmation: requiresOverwriteConfirmation,
  );
}
