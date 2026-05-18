import 'package:fastlane_cli/src/localization/i18n/strings.g.dart';
import 'package:fastlane_cli/src/localization/locale_code.dart';
import 'package:fastlane_cli/src/localization/run_status_label.dart';
import 'package:fastlane_cli/src/model/run_session.dart';
import 'package:test/test.dart';

void main() {
  group('slang `t` accessor', () {
    test('Turkish locale resolves expected keys', () {
      LocaleSettings.setLocaleSync(AppLocale.tr);
      expect(t.homeTitle, 'Ana Sayfa');
      expect(t.androidTitle, 'Android');
      expect(t.shellBrand, contains('Fast'));
      expect(t.runConfirmMessage(actionTitle: 'X'), contains('X'));
      expect(t.status.idle, 'Bekleniyor');
      expect(t.status.dryRun, 'Dry-run tamamlandı');
    });

    test('English locale resolves expected keys', () {
      LocaleSettings.setLocaleSync(AppLocale.en);
      expect(t.homeTitle, 'Home');
      expect(t.footerHints, contains('Quit'));
      expect(t.status.failed, 'Failed');
      expect(t.status.succeeded, 'Succeeded');
    });

    test('LocaleSettings.setLocaleSync swaps the `t` accessor', () {
      LocaleSettings.setLocaleSync(AppLocale.tr);
      expect(t.homeTitle, 'Ana Sayfa');
      LocaleSettings.setLocaleSync(AppLocale.en);
      expect(t.homeTitle, 'Home');
    });

    test('every top-level sentinel key differs across locales', () {
      LocaleSettings.setLocaleSync(AppLocale.tr);
      final trHome = t.homeTitle;
      final trRunTitle = t.runTitle;
      final trBack = t.back;

      LocaleSettings.setLocaleSync(AppLocale.en);
      expect(t.homeTitle, isNot(equals(trHome)));
      expect(t.runTitle, isNot(equals(trRunTitle)));
      expect(t.back, isNot(equals(trBack)));
    });
  });

  group('RunStatusLocalization extension', () {
    test('emits the running label in both locales', () {
      LocaleSettings.setLocaleSync(AppLocale.tr);
      final trRunning = RunStatus.running.label;
      expect(trRunning, isNotEmpty);
      expect(trRunning, t.status.running);

      LocaleSettings.setLocaleSync(AppLocale.en);
      final enRunning = RunStatus.running.label;
      expect(enRunning, isNotEmpty);
      expect(enRunning, t.status.running);
      expect(enRunning, isNot(equals(trRunning)));
    });

    test('covers every RunStatus with non-empty, locale-distinct labels', () {
      LocaleSettings.setLocaleSync(AppLocale.tr);
      final trLabels = <RunStatus, String>{
        for (final status in RunStatus.values) status: status.label,
      };

      LocaleSettings.setLocaleSync(AppLocale.en);
      final enLabels = <RunStatus, String>{
        for (final status in RunStatus.values) status: status.label,
      };

      expect(trLabels, hasLength(RunStatus.values.length));
      for (final status in RunStatus.values) {
        expect(trLabels[status], isNotEmpty,
            reason: 'TR label for $status was empty');
        expect(enLabels[status], isNotEmpty,
            reason: 'EN label for $status was empty');
        expect(
          trLabels[status],
          isNot(equals(enLabels[status])),
          reason: 'TR and EN labels match for $status — '
              'probably a missing locale branch',
        );
      }
    });
  });

  group('LocaleCode <-> AppLocale adapter', () {
    test('round-trips both supported locales', () {
      expect(LocaleCode.tr.toAppLocale(), AppLocale.tr);
      expect(LocaleCode.en.toAppLocale(), AppLocale.en);
      expect(AppLocale.tr.toLocaleCode(), LocaleCode.tr);
      expect(AppLocale.en.toLocaleCode(), LocaleCode.en);
    });
  });
}
