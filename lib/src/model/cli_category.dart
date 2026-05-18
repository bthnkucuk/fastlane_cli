import '../localization/locale_code.dart';

class CliCategory {
  const CliCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.actionIds,
  });

  final String id;
  final Map<LocaleCode, String> title;
  final Map<LocaleCode, String> description;
  final List<String> actionIds;

  String titleFor(LocaleCode locale) {
    return title[locale] ?? title[LocaleCode.tr] ?? title.values.first;
  }

  String descriptionFor(LocaleCode locale) {
    if (description.isEmpty) {
      return '';
    }
    return description[locale] ??
        description[LocaleCode.tr] ??
        description.values.first;
  }
}
