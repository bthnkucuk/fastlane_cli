import '../localization/locale_code.dart';

class GuideTopic {
  const GuideTopic({
    required this.id,
    required this.title,
    required this.summary,
    required this.checklist,
    required this.paths,
    this.markdown,
  });

  final String id;
  final Map<LocaleCode, String> title;
  final Map<LocaleCode, String> summary;
  final Map<LocaleCode, List<String>> checklist;
  final Map<LocaleCode, List<String>> paths;

  /// Optional pre-authored markdown body, per locale.
  ///
  /// When provided, [markdownFor] returns this verbatim. Otherwise
  /// [markdownFor] synthesizes markdown from [checklist] + [paths].
  ///
  /// NOTE FOR SLANG MIGRATION (Track Slang agent): once the registry's
  /// string content moves to slang YAML, populate this map from the
  /// generated localizations. The synthesized fallback below preserves
  /// existing rendering until that switch happens — no UI regression
  /// expected at merge time.
  final Map<LocaleCode, String>? markdown;

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

  /// Returns a markdown source string for this guide in the given locale.
  ///
  /// If an explicit [markdown] entry exists for the locale (or for the
  /// fallback `tr` locale), it is returned as-is. Otherwise the method
  /// synthesizes a markdown document from the existing checklist + paths,
  /// rendering checklist items as `-` list entries and paths as a
  /// fenced code-style line list.
  String markdownFor(LocaleCode locale) {
    final explicit = markdown?[locale] ?? markdown?[LocaleCode.tr];
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final buf = StringBuffer();
    final checklistItems = checklistFor(locale);
    for (final line in checklistItems) {
      buf.writeln('- $line');
    }
    final pathItems = pathsFor(locale);
    if (pathItems.isNotEmpty) {
      if (checklistItems.isNotEmpty) buf.writeln();
      for (final p in pathItems) {
        buf.writeln('`$p`');
      }
    }
    return buf.toString();
  }
}
