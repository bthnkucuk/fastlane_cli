import '../localization/locale_code.dart';

class GuideTopic {
  const GuideTopic({
    required this.id,
    required this.title,
    required this.summary,
    required this.checklist,
    required this.paths,
  });

  final String id;
  final Map<LocaleCode, String> title;
  final Map<LocaleCode, String> summary;
  final Map<LocaleCode, List<String>> checklist;
  final Map<LocaleCode, List<String>> paths;

  String titleFor(LocaleCode locale) {
    return title[locale] ?? title[LocaleCode.tr] ?? title.values.first;
  }

  String summaryFor(LocaleCode locale) {
    return summary[locale] ?? summary[LocaleCode.tr] ?? summary.values.first;
  }

  List<String> checklistFor(LocaleCode locale) {
    return checklist[locale] ?? checklist[LocaleCode.tr] ?? const <String>[];
  }

  List<String> pathsFor(LocaleCode locale) {
    return paths[locale] ?? paths[LocaleCode.tr] ?? const <String>[];
  }
}
