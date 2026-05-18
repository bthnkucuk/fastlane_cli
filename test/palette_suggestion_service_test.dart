import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/model/palette_suggestion.dart';
import 'package:fastlane_cli/src/services/palette_suggestion_service.dart';
import 'package:test/test.dart';

import 'support/profile_factory.dart';

void main() {
  group('PaletteSuggestionService', () {
    const service = PaletteSuggestionService();

    test('returns pages, guides and actions for root slash query', () {
      final action = makeFastlaneAction(
        id: 'android_internal_testing',
        categoryId: 'android',
        lane: 'internal_testing',
        platform: 'android',
      );
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>[action.id]),
        ],
      );

      final suggestions = service.build(
        profile: profile,
        locale: AppLocale.tr,
        query: '/',
      );

      expect(suggestions, isNotEmpty);
      expect(
        suggestions.any((item) => item.type == PaletteSuggestionType.page),
        isTrue,
      );
      expect(
        suggestions.any((item) => item.type == PaletteSuggestionType.guide),
        isTrue,
      );
      expect(
        suggestions.any((item) => item.actionId == 'android_internal_testing'),
        isTrue,
      );
    });

    test('filters suggestions with slash query', () {
      final action = CliAction(
        id: 'ios_download_metadata',
        categoryId: 'ios',
        title: const <AppLocale, String>{
          AppLocale.tr: 'iOS metadata indir',
          AppLocale.en: 'Download iOS metadata',
        },
        description: const <AppLocale, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.fastlane,
          platform: 'ios',
          lane: 'download_metadata',
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'ios', actionIds: <String>[action.id]),
        ],
      );

      final suggestions = service.build(
        profile: profile,
        locale: AppLocale.tr,
        query: '/metadata',
      );

      expect(suggestions, isNotEmpty);
      expect(
        suggestions.any((item) => item.actionId == 'ios_download_metadata'),
        isTrue,
      );
    });

    test('returns quit command suggestion for q', () {
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      final suggestions = service.build(
        profile: profile,
        locale: AppLocale.tr,
        query: '/q',
      );

      expect(
        suggestions.any(
          (item) =>
              item.type == PaletteSuggestionType.command &&
              item.commandId == 'quit',
        ),
        isTrue,
      );
    });
  });
}
