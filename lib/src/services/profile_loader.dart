import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../localization/i18n/strings.g.dart';
import '../localization/parse_locale.dart';
import '../model/cli_action.dart';
import '../model/cli_category.dart';
import '../model/cli_profile.dart';
import 'runner_resolver.dart';

class ProfileLoader {
  const ProfileLoader({RunnerResolver runnerResolver = const RunnerResolver()})
    : _runnerResolver = runnerResolver;

  final RunnerResolver _runnerResolver;

  Future<CliProfile> load(String profilePath) async {
    final profileFile = File(profilePath);
    if (!profileFile.existsSync()) {
      throw FormatException('Profile not found: $profilePath');
    }

    final source = await profileFile.readAsString();
    final yaml = loadYaml(source);
    if (yaml is! YamlMap) {
      throw const FormatException('Profile must be a YAML map.');
    }

    final appRoot = _yamlMapToMap(yaml);
    final profileDirectory = profileFile.parent.absolute.path;

    // Resolve the runner directory once, before merging, so that the bundled
    // `cli_profile.base.yaml` can be located even when the profile omits
    // `fastlane_runner_path`.
    final runnerOverride = _readRunnerOverride(appRoot, profileDirectory);
    final resolvedRunnerDir = await _runnerResolver.resolve(
      profileOverride: runnerOverride,
    );

    final root = _maybeMergeBaseProfile(appRoot, resolvedRunnerDir);

    final appMap = _requireMap(root, 'app');
    final appName = _requireString(appMap, 'name');
    final appRootRaw = _requireString(appMap, 'root_path');
    final fastlanePath = _stringOrDefault(appMap, 'fastlane_path', 'fastlane');

    final appRootPath = p.normalize(
      p.isAbsolute(appRootRaw)
          ? appRootRaw
          : p.join(profileDirectory, appRootRaw),
    );

    // Store the runner path so that `CliProfile.fastlaneRunnerDirectoryPath`
    // (which joins it under appRootPath) resolves back to the absolute path
    // we just discovered. A relative path keeps the existing model's
    // `$appRootPath/$fastlaneRunnerPath` join semantics intact.
    final fastlaneRunnerPath = p.relative(
      resolvedRunnerDir,
      from: appRootPath,
    );

    final defaultLocale = parseLocale(
      _stringOrDefault(appMap, 'default_locale', 'tr'),
      fallback: AppLocale.tr,
    );

    final supportedLocales = _parseSupportedLocales(root, defaultLocale);
    final categories = _parseCategories(_requireList(root, 'categories'));
    final defaultOptions = _parseDefaultOptions(root['default_options']);
    final actions = _applyDefaultOptions(
      _parseActions(_requireList(root, 'actions')),
      defaultOptions,
    );
    final shortcuts = _parseStringList(root['shortcuts']);

    _validateProfileConsistency(categories, actions, shortcuts);

    return CliProfile(
      appName: appName,
      profilePath: profileFile.absolute.path,
      appRootPath: appRootPath,
      fastlanePath: fastlanePath,
      fastlaneRunnerPath: fastlaneRunnerPath,
      defaultLocale: defaultLocale,
      supportedLocales: supportedLocales,
      categories: categories,
      actions: actions,
      shortcutActionIds: shortcuts,
    );
  }

  /// Reads `app.fastlane_runner_path` from the unmerged profile and, if
  /// relative, resolves it against the profile directory's nearest plausible
  /// `app.root_path`. Returns `null` when the field is absent or empty so the
  /// runner resolver can fall through to its auto-detection branches.
  String? _readRunnerOverride(
    Map<String, Object?> appRoot,
    String profileDirectory,
  ) {
    final appMap = appRoot['app'];
    if (appMap is! Map) {
      return null;
    }
    final appOnly = appMap.map((key, value) => MapEntry(key.toString(), value));

    final runnerRaw = appOnly['fastlane_runner_path'];
    if (runnerRaw is! String || runnerRaw.trim().isEmpty) {
      return null;
    }

    final appRootRaw = _stringOrDefault(appOnly, 'root_path', '.');
    final appRootAbs = p.normalize(
      p.isAbsolute(appRootRaw)
          ? appRootRaw
          : p.join(profileDirectory, appRootRaw),
    );
    final trimmed = runnerRaw.trim();
    return p.normalize(
      p.isAbsolute(trimmed) ? trimmed : p.join(appRootAbs, trimmed),
    );
  }

  Map<String, Object?> _maybeMergeBaseProfile(
    Map<String, Object?> appRoot,
    String resolvedRunnerDir,
  ) {
    final baseFile = File(p.join(resolvedRunnerDir, 'cli_profile.base.yaml'));
    if (!baseFile.existsSync()) {
      return appRoot;
    }

    final baseYaml = loadYaml(baseFile.readAsStringSync());
    if (baseYaml is! YamlMap) {
      return appRoot;
    }
    final baseMap = _yamlMapToMap(baseYaml);

    return _mergeProfileMaps(baseMap, appRoot);
  }

  Map<String, Object?> _mergeProfileMaps(
    Map<String, Object?> base,
    Map<String, Object?> override,
  ) {
    final result = <String, Object?>{...base};
    for (final entry in override.entries) {
      final key = entry.key;
      final overrideValue = entry.value;
      final baseValue = result[key];
      result[key] = _mergeProfileValues(key, baseValue, overrideValue);
    }
    return result;
  }

  Object? _mergeProfileValues(String key, Object? base, Object? override) {
    if (override == null) {
      return base;
    }
    if (base == null) {
      return override;
    }

    if (base is Map<String, Object?> && override is Map<String, Object?>) {
      return _mergeProfileMaps(base, override);
    }
    if (base is Map && override is Map) {
      return _mergeProfileMaps(
        base.map((k, v) => MapEntry(k.toString(), v)),
        override.map((k, v) => MapEntry(k.toString(), v)),
      );
    }

    if ((key == 'categories' || key == 'actions') &&
        base is List &&
        override is List) {
      return _mergeListsById(base, override);
    }

    return override;
  }

  List<Object?> _mergeListsById(List<Object?> base, List<Object?> override) {
    String? idOf(Object? entry) {
      if (entry is Map) {
        final value = entry['id'];
        if (value is String) {
          return value.trim();
        }
      }
      return null;
    }

    final merged = <Object?>[];
    final indexById = <String, int>{};

    for (final item in base) {
      final id = idOf(item);
      if (id != null && id.isNotEmpty) {
        indexById[id] = merged.length;
      }
      merged.add(item);
    }

    for (final item in override) {
      final id = idOf(item);
      if (id != null && id.isNotEmpty && indexById.containsKey(id)) {
        merged[indexById[id]!] = item;
      } else {
        if (id != null && id.isNotEmpty) {
          indexById[id] = merged.length;
        }
        merged.add(item);
      }
    }

    return merged;
  }

  void _validateProfileConsistency(
    List<CliCategory> categories,
    List<CliAction> actions,
    List<String> shortcuts,
  ) {
    final categoryIds = categories.map((item) => item.id).toSet();
    final actionIds = actions.map((item) => item.id).toSet();

    for (final action in actions) {
      if (!categoryIds.contains(action.categoryId)) {
        throw FormatException(
          'Action "${action.id}" references unknown category "${action.categoryId}".',
        );
      }
    }

    for (final shortcutId in shortcuts) {
      if (!actionIds.contains(shortcutId)) {
        throw FormatException(
          'Shortcut references unknown action "$shortcutId".',
        );
      }
    }
  }

  List<CliCategory> _parseCategories(List<Object?> rawCategories) {
    final categories = <CliCategory>[];
    for (final entry in rawCategories) {
      final map = _asMap(entry, context: 'category');
      categories.add(
        CliCategory(
          id: _requireString(map, 'id'),
          title: _parseLocalizedField(map, 'title'),
          description: _parseLocalizedField(
            map,
            'description',
            required: false,
          ),
          actionIds: _parseStringList(map['actions']),
        ),
      );
    }
    return categories;
  }

  List<CliAction> _parseActions(List<Object?> rawActions) {
    final actions = <CliAction>[];
    for (final entry in rawActions) {
      final map = _asMap(entry, context: 'action');
      final commandMap = _requireMap(map, 'command');
      final commandType = ActionCommandType.parse(
        _requireString(commandMap, 'type'),
      );

      final command = switch (commandType) {
        ActionCommandType.fastlane => CliActionCommand(
          type: commandType,
          platform: _stringOrNull(commandMap['platform']),
          lane: _requireString(commandMap, 'lane'),
          options: _parseStringMap(commandMap['options']),
        ),
        ActionCommandType.flutter => CliActionCommand(
          type: commandType,
          arguments: _parseStringList(commandMap['args']),
        ),
        ActionCommandType.dart => CliActionCommand(
          type: commandType,
          arguments: _parseStringList(commandMap['args']),
        ),
        ActionCommandType.custom => CliActionCommand(
          type: commandType,
          executable: _requireString(commandMap, 'executable'),
          arguments: _parseStringList(commandMap['args']),
        ),
      };

      final preflight = _parseStringList(
        map['preflight'],
      ).map(PreflightCheck.parse).toList();

      actions.add(
        CliAction(
          id: _requireString(map, 'id'),
          categoryId: _requireString(map, 'category'),
          title: _parseLocalizedField(map, 'title'),
          description: _parseLocalizedField(
            map,
            'description',
            required: false,
          ),
          command: command,
          preflightChecks: preflight,
          shortcut: _boolOrDefault(map, 'shortcut', false),
          requiresConfirmation: _boolOrDefault(
            map,
            'requires_confirmation',
            false,
          ),
          requiresOverwriteConfirmation: _boolOrDefault(
            map,
            'requires_overwrite_confirmation',
            false,
          ),
        ),
      );
    }
    return actions;
  }

  /// Parses the optional top-level `default_options` block — a flat map of
  /// option key → scalar value applied to every command action. Absent or
  /// `null` yields an empty map (no-op). A non-map value, or any nested
  /// map / list value, is rejected with a [FormatException] so the consumer
  /// gets a clear error instead of a silently-stringified `{...}`.
  Map<String, String> _parseDefaultOptions(Object? value) {
    if (value == null) {
      return const <String, String>{};
    }
    if (value is! Map) {
      throw FormatException(
        '"default_options" must be a map of string option values, '
        'got ${value.runtimeType}.',
      );
    }
    final parsed = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final optionValue = entry.value;
      if (optionValue is Map || optionValue is List) {
        throw FormatException(
          '"default_options.$key" must be a scalar value, '
          'got ${optionValue.runtimeType}.',
        );
      }
      parsed[key] = optionValue == null ? '' : optionValue.toString();
    }
    return parsed;
  }

  /// Folds [defaultOptions] underneath every command action's own
  /// `command.options`. Per-action options win on key collision. Actions
  /// whose command carries no options (e.g. `flutter` / `dart` / `custom`)
  /// are left untouched. Returns a fresh list; the input is not mutated.
  List<CliAction> _applyDefaultOptions(
    List<CliAction> actions,
    Map<String, String> defaultOptions,
  ) {
    if (defaultOptions.isEmpty) {
      return actions;
    }
    return actions.map((action) {
      final command = action.command;
      // Only fastlane commands carry an options map; other command types
      // ignore options entirely, so injecting defaults there would be dead
      // weight. Skip them to keep the resolved action minimal.
      if (command.type != ActionCommandType.fastlane) {
        return action;
      }
      return CliAction(
        id: action.id,
        categoryId: action.categoryId,
        title: action.title,
        description: action.description,
        command: CliActionCommand(
          type: command.type,
          platform: command.platform,
          lane: command.lane,
          options: <String, String>{...defaultOptions, ...command.options},
          arguments: command.arguments,
          executable: command.executable,
        ),
        preflightChecks: action.preflightChecks,
        shortcut: action.shortcut,
        requiresConfirmation: action.requiresConfirmation,
        requiresOverwriteConfirmation: action.requiresOverwriteConfirmation,
      );
    }).toList();
  }

  Map<AppLocale, String> _parseLocalizedField(
    Map<String, Object?> map,
    String key, {
    bool required = true,
  }) {
    final value = map[key];
    if (value == null) {
      if (required) {
        throw FormatException('Missing required localized field "$key".');
      }
      return const <AppLocale, String>{};
    }

    if (value is String) {
      return {AppLocale.tr: value, AppLocale.en: value};
    }

    if (value is Map) {
      final parsed = <AppLocale, String>{};
      final trValue = value['tr'];
      final enValue = value['en'];
      if (trValue is String && trValue.trim().isNotEmpty) {
        parsed[AppLocale.tr] = trValue.trim();
      }
      if (enValue is String && enValue.trim().isNotEmpty) {
        parsed[AppLocale.en] = enValue.trim();
      }
      if (parsed.isEmpty) {
        throw FormatException('Localized field "$key" requires tr or en text.');
      }
      if (!parsed.containsKey(AppLocale.tr)) {
        parsed[AppLocale.tr] = parsed.values.first;
      }
      if (!parsed.containsKey(AppLocale.en)) {
        parsed[AppLocale.en] = parsed.values.first;
      }
      return parsed;
    }

    throw FormatException('Localized field "$key" must be string or map.');
  }

  List<AppLocale> _parseSupportedLocales(
    Map<String, Object?> root,
    AppLocale defaultLocale,
  ) {
    final app = _requireMap(root, 'app');
    final locales = _parseStringList(app['supported_locales'])
        .map((item) => parseLocale(item, fallback: defaultLocale))
        .toSet()
        .toList();
    if (locales.isEmpty) {
      return <AppLocale>[defaultLocale, AppLocale.en];
    }
    if (!locales.contains(defaultLocale)) {
      locales.insert(0, defaultLocale);
    }
    return locales;
  }

  Map<String, String> _parseStringMap(Object? value) {
    if (value == null) {
      return const <String, String>{};
    }
    final map = _asMap(value, context: 'map');
    return {
      for (final entry in map.entries)
        entry.key: entry.value == null ? '' : entry.value.toString(),
    };
  }

  List<String> _parseStringList(Object? value) {
    if (value == null) {
      return const <String>[];
    }
    if (value is YamlList) {
      return value.map((item) => item.toString()).toList();
    }
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    throw FormatException('Expected list but got ${value.runtimeType}.');
  }

  Map<String, Object?> _asMap(Object? value, {required String context}) {
    if (value is YamlMap) {
      return _yamlMapToMap(value);
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    throw FormatException(
      'Expected map for $context but got ${value.runtimeType}.',
    );
  }

  Map<String, Object?> _requireMap(Map<String, Object?> parent, String key) {
    final value = parent[key];
    if (value == null) {
      throw FormatException('Missing required map "$key".');
    }
    return _asMap(value, context: key);
  }

  List<Object?> _requireList(Map<String, Object?> parent, String key) {
    final value = parent[key];
    if (value == null) {
      throw FormatException('Missing required list "$key".');
    }
    if (value is YamlList) {
      return value.toList();
    }
    if (value is List) {
      return value;
    }
    throw FormatException('Field "$key" must be a list.');
  }

  String _requireString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw FormatException('Missing required string "$key".');
  }

  String _stringOrDefault(
    Map<String, Object?> map,
    String key,
    String fallback,
  ) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  String? _stringOrNull(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  bool _boolOrDefault(Map<String, Object?> map, String key, bool fallback) {
    final value = map[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    return fallback;
  }

  Map<String, Object?> _yamlMapToMap(YamlMap map) {
    return map.map((key, value) => MapEntry(key.toString(), _yamlValue(value)));
  }

  Object? _yamlValue(Object? value) {
    if (value is YamlMap) {
      return _yamlMapToMap(value);
    }
    if (value is YamlList) {
      return value.map(_yamlValue).toList();
    }
    return value;
  }
}
