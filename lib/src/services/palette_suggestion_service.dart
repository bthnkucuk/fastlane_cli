import '../localization/i18n/strings.g.dart';
import '../localization/locale_code.dart';
import '../model/cli_profile.dart';
import '../model/palette_suggestion.dart';

class PaletteSuggestionService {
  const PaletteSuggestionService();

  List<PaletteSuggestion> build({
    required CliProfile profile,
    required LocaleCode locale,
    required String query,
  }) {
    final normalizedQuery = _normalize(query);
    final suggestions = <PaletteSuggestion>[
      _page(
        id: 'home',
        title: t.palette.homeTitle,
        path: '/',
      ),
      _page(id: 'android', title: t.androidTitle, path: '/android'),
      _page(id: 'ios', title: t.iosTitle, path: '/ios'),
      _page(
        id: 'general',
        title: t.palette.generalTitle,
        path: '/general',
      ),
      _guide(
        id: 'guide_android_metadata',
        title: t.palette.guideAndroidMetadata,
        path: '/guides/android_metadata',
      ),
      _guide(
        id: 'guide_ios_metadata',
        title: t.palette.guideIosMetadata,
        path: '/guides/ios_metadata',
      ),
      ...profile.actions.map(
        (action) => PaletteSuggestion(
          type: PaletteSuggestionType.action,
          id: 'action:${action.id}',
          title: action.titleFor(locale),
          subtitle: action.id,
          actionId: action.id,
        ),
      ),
      _command(
        id: 'command_quit',
        title: t.palette.quitTitle,
        subtitle: t.palette.quitSubtitle,
        commandId: 'quit',
      ),
    ];

    if (normalizedQuery.isEmpty) {
      return suggestions;
    }

    return suggestions.where((item) {
      final haystack = '${item.title} ${item.subtitle}'.toLowerCase();
      return haystack.contains(normalizedQuery);
    }).toList();
  }

  PaletteSuggestion _page({
    required String id,
    required String title,
    required String path,
  }) {
    return PaletteSuggestion(
      type: PaletteSuggestionType.page,
      id: id,
      title: title,
      subtitle: path,
      path: path,
    );
  }

  PaletteSuggestion _guide({
    required String id,
    required String title,
    required String path,
  }) {
    return PaletteSuggestion(
      type: PaletteSuggestionType.guide,
      id: id,
      title: title,
      subtitle: path,
      path: path,
    );
  }

  PaletteSuggestion _command({
    required String id,
    required String title,
    required String subtitle,
    required String commandId,
  }) {
    return PaletteSuggestion(
      type: PaletteSuggestionType.command,
      id: id,
      title: title,
      subtitle: subtitle,
      commandId: commandId,
    );
  }

  String _normalize(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.startsWith('/')) {
      return trimmed.substring(1).trim();
    }
    return trimmed;
  }
}
