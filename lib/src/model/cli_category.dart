import '../localization/i18n/strings.g.dart';

class CliCategory {
  const CliCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.actionIds,
  });

  final String id;
  final Map<AppLocale, String> title;
  final Map<AppLocale, String> description;
  final List<String> actionIds;

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
