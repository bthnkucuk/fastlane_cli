import '../localization/i18n/strings.g.dart';
import '../model/cli_profile.dart';
import '../services/command_builder.dart';
import '../services/command_execution_service.dart';
import '../services/guide_registry.dart';
import '../services/palette_suggestion_service.dart';
import '../services/preflight_validator.dart';
import '../services/run_progress_parser.dart';
import '../services/run_prompt_parser.dart';

class FastlaneCliEnvironment {
  FastlaneCliEnvironment({
    required this.profile,
    required AppLocale initialLocale,
    required this.dryRun,
    required this.commandBuilder,
    required this.executionService,
    required this.preflightValidator,
    required this.guideRegistry,
    this.paletteSuggestionService = const PaletteSuggestionService(),
    this.progressParser = const RunProgressParser(),
    RunPromptParser? promptParser,
  })  : promptParser = promptParser ??
            RunPromptParser(localizer: _SlangPromptLocalizer()),
        _locale = initialLocale {
    LocaleSettings.setLocaleSync(initialLocale);
  }

  final CliProfile profile;
  final bool dryRun;
  final CommandBuilder commandBuilder;
  final CommandExecutionService executionService;
  final PreflightValidator preflightValidator;
  final GuideRegistry guideRegistry;
  final PaletteSuggestionService paletteSuggestionService;
  final RunProgressParser progressParser;
  final RunPromptParser promptParser;

  AppLocale _locale;
  AppLocale get locale => _locale;

  final List<void Function(AppLocale)> _localeListeners = [];

  void addLocaleListener(void Function(AppLocale) listener) {
    _localeListeners.add(listener);
  }

  void removeLocaleListener(void Function(AppLocale) listener) {
    _localeListeners.remove(listener);
  }

  void setLocale(AppLocale locale) {
    if (_locale == locale) return;
    _locale = locale;
    LocaleSettings.setLocaleSync(locale);
    for (final listener in List.of(_localeListeners)) {
      listener(locale);
    }
  }

  void toggleLocale() {
    final supported = profile.supportedLocales;
    if (supported.isEmpty) return;
    final current = supported.indexOf(_locale);
    final next = current < 0 ? 0 : (current + 1) % supported.length;
    setLocale(supported[next]);
  }
}

/// Pulls prompt strings from slang's global `t` accessor so the prompt parser
/// renders labels in the active TUI locale instead of the hard-coded
/// fallback. Lives here (rather than in `run_prompt_parser.dart`) to keep the
/// parser itself slang-free and unit-testable.
class _SlangPromptLocalizer implements PromptLocalizer {
  @override
  String twoFactorBody(int digits) => t.prompt.twoFactorBody(digits: digits);

  @override
  String twoFactorHint(int digits) => t.prompt.twoFactorHint(digits: digits);

  @override
  String trustComputerBody() => t.prompt.trustComputerBody;

  @override
  String chooseIndexBody(int lo, int hi) =>
      t.prompt.chooseIndexBody(lo: lo, hi: hi);

  @override
  String errorWrongLength(int digits) => t.prompt.errorWrongLength(n: digits);

  @override
  String errorOnlyDigits() => t.prompt.errorOnlyDigits;

  @override
  String errorYesOrNo() => t.prompt.errorYesOrNo;

  @override
  String errorOutOfRange(int lo, int hi) =>
      t.prompt.errorOutOfRange(lo: lo, hi: hi);

  @override
  String errorRequired() => t.prompt.errorRequired;
}
