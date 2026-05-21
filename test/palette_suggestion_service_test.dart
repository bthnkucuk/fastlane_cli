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

    test('an empty query returns the full unfiltered suggestion set', () {
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

      final empty = service.build(
        profile: profile,
        locale: AppLocale.tr,
        query: '',
      );
      final whitespace = service.build(
        profile: profile,
        locale: AppLocale.tr,
        query: '   ',
      );
      // A bare slash normalizes to empty too.
      final slash = service.build(
        profile: profile,
        locale: AppLocale.tr,
        query: '/',
      );

      // All three are the same full set: 4 pages + 2 guides + 1 action +
      // 1 quit command.
      expect(empty, hasLength(8));
      expect(whitespace, hasLength(empty.length));
      expect(slash, hasLength(empty.length));
    });

    test('a query matching nothing returns an empty list', () {
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      final suggestions = service.build(
        profile: profile,
        locale: AppLocale.tr,
        query: 'zzz-no-such-thing-zzz',
      );

      expect(suggestions, isEmpty);
    });

    test('matches against the action subtitle (the raw action id)', () {
      // The subtitle is the action id — a query on the id should hit even
      // when the localized title does not contain it.
      final action = makeFastlaneAction(
        id: 'uniqueidtoken',
        categoryId: 'android',
        lane: 'lane',
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
        locale: AppLocale.en,
        query: 'uniqueidtoken',
      );

      expect(
        suggestions.single.actionId,
        'uniqueidtoken',
      );
    });

    test('a profile with no actions still surfaces pages, guides and quit', () {
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      final suggestions = service.build(
        profile: profile,
        locale: AppLocale.en,
        query: '',
      );

      // 4 pages + 2 guides + 0 actions + 1 quit command.
      expect(suggestions, hasLength(7));
      expect(
        suggestions.any((s) => s.type == PaletteSuggestionType.action),
        isFalse,
      );
    });
  });
}
