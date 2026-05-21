import '../localization/i18n/strings.g.dart';

enum ActionCommandType {
  fastlane,
  flutter,
  dart,
  custom;

  static ActionCommandType parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'fastlane' => ActionCommandType.fastlane,
      'flutter' => ActionCommandType.flutter,
      'dart' => ActionCommandType.dart,
      'custom' => ActionCommandType.custom,
      _ => throw FormatException('Unknown command type: $value'),
    };
  }
}

enum PreflightCheck {
  androidMetadata('android_metadata'),
  androidMetadataTextOnly('android_metadata_text_only'),
  iosMetadata('ios_metadata');

  const PreflightCheck(this.value);
  final String value;

  static PreflightCheck parse(String value) {
    final normalized = value.trim().toLowerCase();
    for (final item in values) {
      if (item.value == normalized) {
        return item;
      }
    }
    throw FormatException('Unknown preflight check: $value');
  }
}

class CliActionCommand {
  const CliActionCommand({
    required this.type,
    this.platform,
    this.lane,
    this.options = const <String, String>{},
    this.arguments = const <String>[],
    this.executable,
  });

  final ActionCommandType type;
  final String? platform;
  final String? lane;
  final Map<String, String> options;
  final List<String> arguments;
  final String? executable;
}

class CliAction {
  const CliAction({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.command,
    required this.preflightChecks,
    required this.shortcut,
    required this.requiresConfirmation,
    this.requiresOverwriteConfirmation = false,
  });

  final String id;
  final String categoryId;
  final Map<AppLocale, String> title;
  final Map<AppLocale, String> description;
  final CliActionCommand command;
  final List<PreflightCheck> preflightChecks;
  final bool shortcut;
  final bool requiresConfirmation;
  final bool requiresOverwriteConfirmation;

  String titleFor(AppLocale locale) {
    return title[locale] ?? title[AppLocale.tr] ?? title.values.first;
  }

  String descriptionFor(AppLocale locale) {
    if (description.isEmpty) {
      return '';
    }
    return description[locale] ??
        description[AppLocale.tr] ??
        description.values.first;
  }
}
