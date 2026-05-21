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
    this.packageName,
    this.bundleId,
  }) : actionsById = {for (final action in actions) action.id: action};

  final String appName;
  final String profilePath;
  final String appRootPath;
  final String fastlanePath;
  final String fastlaneRunnerPath;

  /// Optional Android `applicationId`, declared under the profile's `app:`
  /// block as `app.package_name`. When set, [ProfileLoader] folds it into
  /// every fastlane action's resolved `command.options` as the `package_name`
  /// option key — at the LOWEST precedence (below `default_options`, below a
  /// per-action `command.options` entry, below a `--option` CLI flag).
  final String? packageName;

  /// Optional iOS bundle id, declared under the profile's `app:` block as
  /// `app.bundle_id`. When set, [ProfileLoader] folds it into every fastlane
  /// action's resolved `command.options` as the `app_identifier` option key
  /// (the key `resolve_identifier` in `fastlane/common_helpers.rb` reads) —
  /// at the same lowest precedence as [packageName].
  final String? bundleId;
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
