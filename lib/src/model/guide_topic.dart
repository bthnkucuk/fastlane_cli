import '../localization/i18n/strings.g.dart';

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
  final Map<AppLocale, String> title;
  final Map<AppLocale, String> summary;
  final Map<AppLocale, List<String>> checklist;
  final Map<AppLocale, List<String>> paths;

  /// Optional pre-authored markdown body, per locale.
  ///
  /// When provided, [markdownFor] returns this verbatim. Otherwise
  /// [markdownFor] synthesizes markdown from [checklist] + [paths].
  final Map<AppLocale, String>? markdown;

  String titleFor(AppLocale locale) {
    return title[locale] ?? title[AppLocale.tr] ?? title.values.first;
  }

  String summaryFor(AppLocale locale) {
    return summary[locale] ?? summary[AppLocale.tr] ?? summary.values.first;
  }

  List<String> checklistFor(AppLocale locale) {
    return checklist[locale] ?? checklist[AppLocale.tr] ?? const <String>[];
  }

  List<String> pathsFor(AppLocale locale) {
    return paths[locale] ?? paths[AppLocale.tr] ?? const <String>[];
  }

  /// Returns a markdown source string for this guide in the given locale.
  ///
  /// If an explicit [markdown] entry exists for the locale (or for the
  /// fallback `tr` locale), it is returned as-is. Otherwise the method
  /// synthesizes a markdown document from the existing checklist + paths,
  /// rendering checklist items as `-` list entries and paths as a
  /// fenced code-style line list.
  String markdownFor(AppLocale locale) {
    final explicit = markdown?[locale] ?? markdown?[AppLocale.tr];
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
