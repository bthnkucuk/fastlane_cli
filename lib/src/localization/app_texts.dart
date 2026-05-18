import '../model/run_session.dart';
import 'locale_code.dart';

class AppTexts {
  const AppTexts(this.locale);

  final LocaleCode locale;

  bool get _isTr => locale == LocaleCode.tr;

  String get homeTitle => _isTr ? 'Ana Sayfa' : 'Home';
  String get androidTitle => 'Android';
  String get iosTitle => 'iOS';
  String get generalTitle => _isTr ? 'Genel' : 'General';
  String get guidesTitle => _isTr ? 'Kılavuz' : 'Guides';
  String get runTitle => _isTr ? 'Çalıştır' : 'Run';
  String get shortcuts => _isTr ? 'Hızlı Erişim' : 'Shortcuts';
  String get categories => _isTr ? 'Kategoriler' : 'Categories';
  String get noAction => _isTr ? 'Aksiyon bulunamadı.' : 'No actions found.';
  String get pressEnterToRun => _isTr ? 'Enter: Çalıştır' : 'Enter: Execute';
  String get upDownNavigate =>
      _isTr ? '↑/↓: Seçim değiştir' : '↑/↓: Change selection';
  String get footerHints => _isTr
      ? 'A:Android I:iOS G:Genel H:Ana D:Guide L:Dil Q:Çıkış'
      : 'A:Android I:iOS G:General H:Home D:Guide L:Lang Q:Quit';
  String get lastRun => _isTr ? 'Son Çalıştırma' : 'Last Run';
  String get command => _isTr ? 'Komut' : 'Command';
  String get logs => _isTr ? 'Loglar' : 'Logs';
  String get progress => _isTr ? 'İlerleme' : 'Progress';
  String get currentFile => _isTr ? 'Aktif Dosya' : 'Current File';
  String get waitingLogs =>
      _isTr ? 'Log akışı bekleniyor...' : 'Waiting for log stream...';
  String get commandPalettePlaceholder =>
      _isTr ? '/ sayfa veya aksiyon ara' : '/ search pages or actions';
  String get commandPaletteTitle => _isTr ? 'Komut Paleti' : 'Command Palette';
  String get commandPaletteNoResult =>
      _isTr ? 'Eşleşme bulunamadı' : 'No matches';
  String get shellBrand => '⚡ Fast CLI';
  String get pages => _isTr ? 'Sayfalar' : 'Pages';
  String get validationFailed =>
      _isTr ? 'Doğrulama başarısız' : 'Validation failed';
  String get blockedByGuide => _isTr
      ? 'Aksiyon kılavuz eksikleri nedeniyle durduruldu.'
      : 'Action blocked due to guide/preflight issues.';
  String get runConfirmTitle => _isTr ? 'Çalıştırma Onayı' : 'Run Confirmation';
  String runConfirmMessage(String actionTitle) => _isTr
      ? '"$actionTitle" aksiyonunu çalıştırmak istiyor musun?'
      : 'Do you want to run "$actionTitle"?';
  String get runConfirmHint => _isTr
      ? 'Y/Enter: Onayla · N/Esc: İptal'
      : 'Y/Enter: Confirm · N/Esc: Cancel';
  String get runConfirmApprove =>
      _isTr ? 'Onayla (Y/Enter)' : 'Confirm (Y/Enter)';
  String get runConfirmCancel => _isTr ? 'İptal (N/Esc)' : 'Cancel (N/Esc)';
  String get quitConfirmTitle => _isTr ? 'Çıkış Onayı' : 'Quit Confirmation';
  String get quitConfirmMessage => _isTr
      ? 'Uygulamadan çıkmak istediğine emin misin?'
      : 'Are you sure you want to quit?';
  String get retry => _isTr ? 'R: Tekrar dene' : 'R: Retry';
  String get back => _isTr ? 'B: Geri' : 'B: Back';
  String get copyOutput =>
      _isTr ? 'C/Ctrl+Shift+C: Çıktıyı kopyala' : 'C/Ctrl+Shift+C: Copy output';
  String get copiedOutput =>
      _isTr ? 'Çıktı panoya kopyalandı.' : 'Output copied to clipboard.';
  String get confirmPrompt => _isTr
      ? 'Bu aksiyon onay gerektirir. Y ile onayla.'
      : 'This action requires confirmation. Press Y to continue.';
  String get guideRetry =>
      _isTr ? 'R: Bu aksiyonu tekrar çalıştır' : 'R: Retry this action';
  String get guideFallback =>
      _isTr ? 'Bu konu için kılavuz yok.' : 'No guide for this topic.';
  String get dryRunLabel => _isTr ? 'Dry-run (simülasyon)' : 'Dry-run';
  String get localeLabel => _isTr ? 'Dil' : 'Language';

  String statusLabel(RunStatus status) {
    return switch (status) {
      RunStatus.idle => _isTr ? 'Bekleniyor' : 'Idle',
      RunStatus.validating => _isTr ? 'Doğrulanıyor' : 'Validating',
      RunStatus.blocked => _isTr ? 'Bloklandı' : 'Blocked',
      RunStatus.confirmationRequired =>
        _isTr ? 'Onay Bekliyor' : 'Needs Confirmation',
      RunStatus.running => _isTr ? 'Çalışıyor' : 'Running',
      RunStatus.succeeded => _isTr ? 'Başarılı' : 'Succeeded',
      RunStatus.failed => _isTr ? 'Başarısız' : 'Failed',
      RunStatus.dryRun => _isTr ? 'Dry-run tamamlandı' : 'Dry-run completed',
    };
  }
}
