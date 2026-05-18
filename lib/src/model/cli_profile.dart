import 'cli_action.dart';
import 'cli_category.dart';
import '../localization/i18n/strings.g.dart';

class CliProfile {
  CliProfile({
    required this.appName,
    required this.profilePath,
    required this.appRootPath,
    required this.fastlanePath,
    required this.fastlaneRunnerPath,
    required this.defaultLocale,
    required this.supportedLocales,
    required this.categories,
    required this.actions,
    required this.shortcutActionIds,
  }) : actionsById = {for (final action in actions) action.id: action};

  final String appName;
  final String profilePath;
  final String appRootPath;
  final String fastlanePath;
  final String fastlaneRunnerPath;
  final AppLocale defaultLocale;
  final List<AppLocale> supportedLocales;
  final List<CliCategory> categories;
  final List<CliAction> actions;
  final List<String> shortcutActionIds;
  final Map<String, CliAction> actionsById;

  String get fastlaneDirectoryPath =>
      _normalizePath('$appRootPath/$fastlanePath');

  String get fastlaneRunnerDirectoryPath =>
      _normalizePath('$appRootPath/$fastlaneRunnerPath');

  List<CliAction> actionsForCategory(String categoryId) {
    CliCategory? category;
    for (final item in categories) {
      if (item.id == categoryId) {
        category = item;
        break;
      }
    }
    if (category == null) {
      return actions.where((item) => item.categoryId == categoryId).toList();
    }
    return category.actionIds
        .map(actionsById.getOrNull)
        .whereType<CliAction>()
        .toList();
  }

  List<CliAction> get shortcutActions {
    final fromProfile = shortcutActionIds
        .map(actionsById.getOrNull)
        .whereType<CliAction>()
        .toList();
    if (fromProfile.isNotEmpty) {
      return fromProfile;
    }
    return actions.where((action) => action.shortcut).toList();
  }
}

extension<K, V> on Map<K, V> {
  V? getOrNull(K key) => containsKey(key) ? this[key] : null;
}

String _normalizePath(String path) {
  return path.replaceAll('//', '/');
}
