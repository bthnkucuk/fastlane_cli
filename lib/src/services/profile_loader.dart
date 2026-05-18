import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../localization/locale_code.dart';
import '../model/cli_action.dart';
import '../model/cli_category.dart';
import '../model/cli_profile.dart';

class ProfileLoader {
  const ProfileLoader();

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
    final root = _maybeMergeBaseProfile(appRoot, profileDirectory);

    final appMap = _requireMap(root, 'app');
    final appName = _requireString(appMap, 'name');
    final appRootRaw = _requireString(appMap, 'root_path');
    final fastlanePath = _stringOrDefault(appMap, 'fastlane_path', 'fastlane');
    final fastlaneRunnerPath = _stringOrDefault(
      appMap,
      'fastlane_runner_path',
      fastlanePath,
    );

    final appRootPath = p.normalize(
      p.isAbsolute(appRootRaw)
          ? appRootRaw
          : p.join(profileDirectory, appRootRaw),
    );

    final defaultLocale = LocaleCode.parse(
      _stringOrDefault(appMap, 'default_locale', 'tr'),
      fallback: LocaleCode.tr,
    );

    final supportedLocales = _parseSupportedLocales(root, defaultLocale);
    final categories = _parseCategories(_requireList(root, 'categories'));
    final actions = _parseActions(_requireList(root, 'actions'));
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

  Map<String, Object?> _maybeMergeBaseProfile(
    Map<String, Object?> appRoot,
    String profileDirectory,
  ) {
    final appMap = appRoot['app'];
    if (appMap is! Map) {
      return appRoot;
    }
    final appOnly = appMap.map((key, value) => MapEntry(key.toString(), value));

    final appRootRaw = _stringOrDefault(appOnly, 'root_path', '.');
    final appRootAbs = p.normalize(
      p.isAbsolute(appRootRaw)
          ? appRootRaw
          : p.join(profileDirectory, appRootRaw),
    );
    final runnerRaw = _stringOrDefault(
      appOnly,
      'fastlane_runner_path',
      _stringOrDefault(appOnly, 'fastlane_path', 'fastlane'),
    );
    final runnerPath = p.normalize(
      p.isAbsolute(runnerRaw) ? runnerRaw : p.join(appRootAbs, runnerRaw),
    );
    final baseFile = File(p.join(runnerPath, 'cli_profile.base.yaml'));
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

  Map<LocaleCode, String> _parseLocalizedField(
    Map<String, Object?> map,
    String key, {
    bool required = true,
  }) {
    final value = map[key];
    if (value == null) {
      if (required) {
        throw FormatException('Missing required localized field "$key".');
      }
      return const <LocaleCode, String>{};
    }

    if (value is String) {
      return {LocaleCode.tr: value, LocaleCode.en: value};
    }

    if (value is Map) {
      final parsed = <LocaleCode, String>{};
      final trValue = value['tr'];
      final enValue = value['en'];
      if (trValue is String && trValue.trim().isNotEmpty) {
        parsed[LocaleCode.tr] = trValue.trim();
      }
      if (enValue is String && enValue.trim().isNotEmpty) {
        parsed[LocaleCode.en] = enValue.trim();
      }
      if (parsed.isEmpty) {
        throw FormatException('Localized field "$key" requires tr or en text.');
      }
      if (!parsed.containsKey(LocaleCode.tr)) {
        parsed[LocaleCode.tr] = parsed.values.first;
      }
      if (!parsed.containsKey(LocaleCode.en)) {
        parsed[LocaleCode.en] = parsed.values.first;
      }
      return parsed;
    }

    throw FormatException('Localized field "$key" must be string or map.');
  }

  List<LocaleCode> _parseSupportedLocales(
    Map<String, Object?> root,
    LocaleCode defaultLocale,
  ) {
    final app = _requireMap(root, 'app');
    final locales = _parseStringList(app['supported_locales'])
        .map((item) => LocaleCode.parse(item, fallback: defaultLocale))
        .toSet()
        .toList();
    if (locales.isEmpty) {
      return <LocaleCode>[defaultLocale, LocaleCode.en];
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
