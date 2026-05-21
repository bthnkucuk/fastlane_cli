import 'package:fastlane_cli/fastlane_cli.dart';

CliProfile createTestProfile({
  required String appRootPath,
  required List<CliAction> actions,
  required List<CliCategory> categories,
  List<String> shortcuts = const <String>[],
}) {
  return CliProfile(
    appName: 'TestApp',
    profilePath: '$appRootPath/profile.yaml',
    appRootPath: appRootPath,
    fastlanePath: 'fastlane',
    fastlaneRunnerPath: 'fastlane',
    defaultLocale: AppLocale.tr,
    supportedLocales: const <AppLocale>[AppLocale.tr, AppLocale.en],
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
    title: <AppLocale, String>{
      AppLocale.tr: id.toUpperCase(),
      AppLocale.en: id.toUpperCase(),
    },
    description: <AppLocale, String>{
      AppLocale.tr: '$id category',
      AppLocale.en: '$id category',
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
    title: const <AppLocale, String>{
      AppLocale.tr: 'Aksiyon',
      AppLocale.en: 'Action',
    },
    description: const <AppLocale, String>{
      AppLocale.tr: 'Açıklama',
      AppLocale.en: 'Description',
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
