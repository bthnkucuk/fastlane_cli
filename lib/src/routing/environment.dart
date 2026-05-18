import '../localization/i18n/strings.g.dart';
import '../localization/locale_code.dart';
import '../model/cli_profile.dart';
import '../services/command_builder.dart';
import '../services/command_execution_service.dart';
import '../services/guide_registry.dart';
import '../services/palette_suggestion_service.dart';
import '../services/preflight_validator.dart';
import '../services/run_progress_parser.dart';

class FastlaneCliEnvironment {
  FastlaneCliEnvironment({
    required this.profile,
    required LocaleCode initialLocale,
    required this.dryRun,
    required this.commandBuilder,
    required this.executionService,
    required this.preflightValidator,
    required this.guideRegistry,
    this.paletteSuggestionService = const PaletteSuggestionService(),
    this.progressParser = const RunProgressParser(),
  }) : _locale = initialLocale {
    LocaleSettings.setLocaleSync(initialLocale.toAppLocale());
  }

  final CliProfile profile;
  final bool dryRun;
  final CommandBuilder commandBuilder;
  final CommandExecutionService executionService;
  final PreflightValidator preflightValidator;
  final GuideRegistry guideRegistry;
  final PaletteSuggestionService paletteSuggestionService;
  final RunProgressParser progressParser;

  LocaleCode _locale;
  LocaleCode get locale => _locale;

  final List<void Function(LocaleCode)> _localeListeners = [];

  void addLocaleListener(void Function(LocaleCode) listener) {
    _localeListeners.add(listener);
  }

  void removeLocaleListener(void Function(LocaleCode) listener) {
    _localeListeners.remove(listener);
  }

  void setLocale(LocaleCode locale) {
    if (_locale == locale) return;
    _locale = locale;
    LocaleSettings.setLocaleSync(locale.toAppLocale());
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
