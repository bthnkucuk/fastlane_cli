import 'package:fastlane_cli/src/localization/app_texts.dart';
import 'package:fastlane_cli/src/localization/i18n/strings.g.dart';
import 'package:fastlane_cli/src/localization/locale_code.dart';
import 'package:fastlane_cli/src/model/run_session.dart';
import 'package:test/test.dart';

void main() {
  group('AppTexts (slang facade)', () {
    void exercise(AppTexts texts) {
      texts.homeTitle;
      texts.androidTitle;
      texts.iosTitle;
      texts.generalTitle;
      texts.guidesTitle;
      texts.runTitle;
      texts.shortcuts;
      texts.categories;
      texts.noAction;
      texts.pressEnterToRun;
      texts.upDownNavigate;
      texts.footerHints;
      texts.lastRun;
      texts.command;
      texts.logs;
      texts.progress;
      texts.currentFile;
      texts.waitingLogs;
      texts.commandPalettePlaceholder;
      texts.commandPaletteTitle;
      texts.commandPaletteNoResult;
      texts.shellBrand;
      texts.pages;
      texts.validationFailed;
      texts.blockedByGuide;
      texts.runConfirmTitle;
      texts.runConfirmMessage('A');
      texts.runConfirmHint;
      texts.runConfirmApprove;
      texts.runConfirmCancel;
      texts.retry;
      texts.back;
      texts.copyOutput;
      texts.copiedOutput;
      texts.confirmPrompt;
      texts.guideRetry;
      texts.guideFallback;
      texts.dryRunLabel;
      texts.localeLabel;
    }

    test('covers getters for Turkish locale', () {
      LocaleSettings.setLocaleSync(AppLocale.tr);
      const texts = AppTexts(LocaleCode.tr);
      exercise(texts);
      expect(texts.homeTitle, contains('Ana'));
      expect(texts.androidTitle, 'Android');
      expect(texts.shellBrand, contains('Fast'));
      expect(texts.runConfirmMessage('X'), contains('X'));
      expect(texts.statusLabel(RunStatus.idle), 'Bekleniyor');
      expect(texts.statusLabel(RunStatus.dryRun), 'Dry-run tamamlandı');
    });

    test('covers getters for English locale', () {
      LocaleSettings.setLocaleSync(AppLocale.en);
      const texts = AppTexts(LocaleCode.en);
      exercise(texts);
      expect(texts.homeTitle, 'Home');
      expect(texts.footerHints, contains('Quit'));
      expect(texts.statusLabel(RunStatus.failed), 'Failed');
      expect(texts.statusLabel(RunStatus.succeeded), 'Succeeded');
    });

    test('statusLabel covers every RunStatus with locale-distinct labels', () {
      // Snapshot both locales by switching slang's current locale.
      final trLabels = <RunStatus, String>{};
      LocaleSettings.setLocaleSync(AppLocale.tr);
      const tr = AppTexts(LocaleCode.tr);
      for (final status in RunStatus.values) {
        trLabels[status] = tr.statusLabel(status);
      }

      final enLabels = <RunStatus, String>{};
      LocaleSettings.setLocaleSync(AppLocale.en);
      const en = AppTexts(LocaleCode.en);
      for (final status in RunStatus.values) {
        enLabels[status] = en.statusLabel(status);
      }

      expect(trLabels, hasLength(RunStatus.values.length));
      for (final status in RunStatus.values) {
        expect(trLabels[status], isNotEmpty,
            reason: 'TR statusLabel($status) boş');
        expect(enLabels[status], isNotEmpty,
            reason: 'EN statusLabel($status) boş');
        expect(
          trLabels[status],
          isNot(equals(enLabels[status])),
          reason: 'TR ve EN aynı: statusLabel($status) — '
              'muhtemelen locale dalı atlandı',
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

    test('LocaleSettings.setLocaleSync swaps the slang `t` accessor', () {
      LocaleSettings.setLocaleSync(AppLocale.tr);
      expect(t.homeTitle, 'Ana Sayfa');
      LocaleSettings.setLocaleSync(AppLocale.en);
      expect(t.homeTitle, 'Home');
    });
  });
}
