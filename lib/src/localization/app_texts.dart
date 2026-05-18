import '../model/run_session.dart';
import 'i18n/strings.g.dart';
import 'locale_code.dart';

/// Thin facade over slang's generated `t` accessor.
///
/// Kept for source-compat with widget code that takes an [AppTexts] argument
/// (and to centralize [statusLabel] mapping). New code can use `t.*` directly.
///
/// The [locale] parameter is retained for API compatibility but is no longer
/// the source of truth: slang's [LocaleSettings.currentLocale] is. Construct
/// this facade after the environment has updated the slang locale.
class AppTexts {
  const AppTexts(this.locale);

  final LocaleCode locale;

  String get homeTitle => t.homeTitle;
  String get androidTitle => t.androidTitle;
  String get iosTitle => t.iosTitle;
  String get generalTitle => t.generalTitle;
  String get guidesTitle => t.guidesTitle;
  String get runTitle => t.runTitle;
  String get shortcuts => t.shortcuts;
  String get categories => t.categories;
  String get noAction => t.noAction;
  String get pressEnterToRun => t.pressEnterToRun;
  String get upDownNavigate => t.upDownNavigate;
  String get footerHints => t.footerHints;
  String get lastRun => t.lastRun;
  String get command => t.command;
  String get logs => t.logs;
  String get progress => t.progress;
  String get currentFile => t.currentFile;
  String get waitingLogs => t.waitingLogs;
  String get commandPalettePlaceholder => t.commandPalettePlaceholder;
  String get commandPaletteTitle => t.commandPaletteTitle;
  String get commandPaletteNoResult => t.commandPaletteNoResult;
  String get shellBrand => t.shellBrand;
  String get pages => t.pages;
  String get validationFailed => t.validationFailed;
  String get blockedByGuide => t.blockedByGuide;
  String get runConfirmTitle => t.runConfirmTitle;
  String runConfirmMessage(String actionTitle) =>
      t.runConfirmMessage(actionTitle: actionTitle);
  String get runConfirmHint => t.runConfirmHint;
  String get runConfirmApprove => t.runConfirmApprove;
  String get runConfirmCancel => t.runConfirmCancel;
  String get quitConfirmTitle => t.quitConfirmTitle;
  String get quitConfirmMessage => t.quitConfirmMessage;
  String get retry => t.retry;
  String get back => t.back;
  String get copyOutput => t.copyOutput;
  String get copiedOutput => t.copiedOutput;
  String get confirmPrompt => t.confirmPrompt;
  String get guideRetry => t.guideRetry;
  String get guideFallback => t.guideFallback;
  String get dryRunLabel => t.dryRunLabel;
  String get localeLabel => t.localeLabel;

  String statusLabel(RunStatus status) {
    return switch (status) {
      RunStatus.idle => t.status.idle,
      RunStatus.validating => t.status.validating,
      RunStatus.blocked => t.status.blocked,
      RunStatus.confirmationRequired => t.status.confirmationRequired,
      RunStatus.running => t.status.running,
      RunStatus.succeeded => t.status.succeeded,
      RunStatus.failed => t.status.failed,
      RunStatus.dryRun => t.status.dryRun,
    };
  }
}
