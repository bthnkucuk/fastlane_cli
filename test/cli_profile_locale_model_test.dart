import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/localization/parse_locale.dart';
import 'package:test/test.dart';

import 'support/profile_factory.dart';

void main() {
  group('parseLocale', () {
    test('maps tr and en case-insensitively', () {
      expect(parseLocale('tr'), AppLocale.tr);
      expect(parseLocale('en'), AppLocale.en);
      expect(parseLocale('EN'), AppLocale.en);
    });

    test('uses fallback for unknown input', () {
      expect(parseLocale('xx'), AppLocale.tr);
      expect(parseLocale('xx', fallback: AppLocale.en), AppLocale.en);
    });

    test('uses fallback for null or empty input', () {
      expect(parseLocale(null), AppLocale.tr);
      expect(parseLocale(''), AppLocale.tr);
      expect(parseLocale('   '), AppLocale.tr);
    });
  });

  group('ActionCommandType', () {
    test('parse accepts known types', () {
      expect(ActionCommandType.parse('fastlane'), ActionCommandType.fastlane);
      expect(ActionCommandType.parse(' FLUTTER '), ActionCommandType.flutter);
      expect(ActionCommandType.parse('dart'), ActionCommandType.dart);
      expect(ActionCommandType.parse('custom'), ActionCommandType.custom);
    });

    test('parse throws for unknown', () {
      expect(() => ActionCommandType.parse('unknown'), throwsFormatException);
    });
  });

  group('PreflightCheck', () {
    test('parse accepts known checks', () {
      expect(PreflightCheck.parse('android_metadata'), PreflightCheck.androidMetadata);
      expect(
        PreflightCheck.parse('android_metadata_text_only'),
        PreflightCheck.androidMetadataTextOnly,
      );
      expect(PreflightCheck.parse('ios_metadata'), PreflightCheck.iosMetadata);
    });

    test('parse throws for unknown', () {
      expect(() => PreflightCheck.parse('nope'), throwsFormatException);
    });
  });

  group('CliAction', () {
    test('titleFor and descriptionFor fall back across locales', () {
      final action = CliAction(
        id: 'a',
        categoryId: 'c',
        title: const <AppLocale, String>{AppLocale.tr: 'TR only'},
        description: const <AppLocale, String>{},
        command: const CliActionCommand(
          type: ActionCommandType.flutter,
          arguments: <String>[],
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      expect(action.titleFor(AppLocale.en), 'TR only');
      expect(action.descriptionFor(AppLocale.en), '');
    });

    test('titleFor uses first value when tr missing', () {
      final action = CliAction(
        id: 'a',
        categoryId: 'c',
        title: const <AppLocale, String>{AppLocale.en: 'EN only'},
        description: const <AppLocale, String>{
          AppLocale.en: 'desc',
        },
        command: const CliActionCommand(
          type: ActionCommandType.flutter,
          arguments: <String>[],
        ),
        preflightChecks: const <PreflightCheck>[],
        shortcut: false,
        requiresConfirmation: false,
      );

      expect(action.titleFor(AppLocale.tr), 'EN only');
      expect(action.descriptionFor(AppLocale.tr), 'desc');
    });
  });

  group('CliProfile', () {
    test('actionsForCategory uses category action order when present', () {
      final a1 = makeFastlaneAction(id: 'one', categoryId: 'c', lane: 'l');
      final a2 = makeFastlaneAction(id: 'two', categoryId: 'c', lane: 'l');
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: <CliAction>[a1, a2],
        categories: <CliCategory>[
          makeCategory(id: 'c', actionIds: <String>['two', 'one']),
        ],
      );

      expect(
        profile.actionsForCategory('c').map((a) => a.id).toList(),
        <String>['two', 'one'],
      );
    });

    test('shortcutActions falls back to shortcut flags when list empty', () {
      final shortcutAction = makeFastlaneAction(
        id: 's',
        categoryId: 'c',
        lane: 'l',
        shortcut: true,
      );
      final other = makeFastlaneAction(id: 'o', categoryId: 'c', lane: 'l');
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: <CliAction>[shortcutAction, other],
        categories: <CliCategory>[
          makeCategory(id: 'c', actionIds: <String>['s', 'o']),
        ],
        shortcuts: const <String>[],
      );

      expect(profile.shortcutActions.single.id, 's');
    });

    test('actionsForCategory filters by id when category entry missing', () {
      final a1 = makeFastlaneAction(id: 'one', categoryId: 'orphan', lane: 'l');
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: <CliAction>[a1],
        categories: const <CliCategory>[],
      );

      expect(profile.actionsForCategory('orphan'), <CliAction>[a1]);
    });
  });
}
