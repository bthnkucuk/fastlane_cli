import 'package:fastlane_cli/src/localization/app_texts.dart';
import 'package:fastlane_cli/src/localization/locale_code.dart';
import 'package:fastlane_cli/src/model/run_session.dart';
import 'package:test/test.dart';

void main() {
  group('AppTexts', () {
    void exercise(AppTexts t) {
      t.homeTitle;
      t.androidTitle;
      t.iosTitle;
      t.generalTitle;
      t.guidesTitle;
      t.runTitle;
      t.shortcuts;
      t.categories;
      t.noAction;
      t.pressEnterToRun;
      t.upDownNavigate;
      t.footerHints;
      t.lastRun;
      t.command;
      t.logs;
      t.progress;
      t.currentFile;
      t.waitingLogs;
      t.commandPalettePlaceholder;
      t.commandPaletteTitle;
      t.commandPaletteNoResult;
      t.shellBrand;
      t.pages;
      t.validationFailed;
      t.blockedByGuide;
      t.runConfirmTitle;
      t.runConfirmMessage('A');
      t.runConfirmHint;
      t.runConfirmApprove;
      t.runConfirmCancel;
      t.retry;
      t.back;
      t.copyOutput;
      t.copiedOutput;
      t.confirmPrompt;
      t.guideRetry;
      t.guideFallback;
      t.dryRunLabel;
      t.localeLabel;
    }

    test('covers getters for Turkish locale', () {
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
      const texts = AppTexts(LocaleCode.en);
      exercise(texts);
      expect(texts.homeTitle, 'Home');
      expect(texts.footerHints, contains('Quit'));
      expect(texts.statusLabel(RunStatus.failed), 'Failed');
      expect(texts.statusLabel(RunStatus.succeeded), 'Succeeded');
    });

    test('statusLabel covers every RunStatus with locale-distinct labels', () {
      const tr = AppTexts(LocaleCode.tr);
      const en = AppTexts(LocaleCode.en);
      // Tüm RunStatus değerleri non-empty olmalı VE TR/EN birbirinden farklı
      // olmalı; aksi halde bir locale dalı sessizce fallback'e düşmüş demektir.
      // Hem `isNotEmpty` (sound bucket) hem de gerçek değer kontratı.
      final labels = <RunStatus, ({String tr, String en})>{
        for (final status in RunStatus.values) status: (tr: tr.statusLabel(status), en: en.statusLabel(status)),
      };
      expect(labels, hasLength(RunStatus.values.length));
      for (final entry in labels.entries) {
        expect(entry.value.tr, isNotEmpty, reason: 'TR statusLabel(${entry.key}) boş');
        expect(entry.value.en, isNotEmpty, reason: 'EN statusLabel(${entry.key}) boş');
        expect(
          entry.value.tr,
          isNot(equals(entry.value.en)),
          reason:
              'TR ve EN aynı: statusLabel(${entry.key}) — '
              'muhtemelen locale dalı atlandı',
        );
      }
    });
  });
}
