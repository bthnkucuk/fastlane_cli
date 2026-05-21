import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart'
    show ProcessCommandExecutionService;
import 'package:fastlane_cli/src/services/guide_registry.dart';
import 'package:test/test.dart';

/// Builds a [FastlaneCliEnvironment] with the given locale wiring. The
/// services are real but inert — none of these tests spawn a process.
FastlaneCliEnvironment _buildEnvironment({
  AppLocale initialLocale = AppLocale.tr,
  List<AppLocale> supportedLocales = const <AppLocale>[
    AppLocale.tr,
    AppLocale.en,
  ],
}) {
  final profile = CliProfile(
    appName: 'TestApp',
    profilePath: '/tmp/app/profile.yaml',
    appRootPath: '/tmp/app',
    fastlanePath: 'fastlane',
    fastlaneRunnerPath: 'fastlane',
    defaultLocale: initialLocale,
    supportedLocales: supportedLocales,
    categories: const <CliCategory>[],
    actions: const <CliAction>[],
    shortcutActionIds: const <String>[],
  );
  return FastlaneCliEnvironment(
    profile: profile,
    initialLocale: initialLocale,
    dryRun: false,
    commandBuilder: const CommandBuilder(),
    executionService: ProcessCommandExecutionService(),
    preflightValidator: const PreflightValidator(),
    guideRegistry: const GuideRegistry(),
  );
}

void main() {
  group('FastlaneCliEnvironment locale management', () {
    test('constructor applies the initial locale', () {
      final env = _buildEnvironment(initialLocale: AppLocale.en);
      expect(env.locale, AppLocale.en);
    });

    test('setLocale changes the locale and notifies listeners', () {
      final env = _buildEnvironment(initialLocale: AppLocale.tr);
      final observed = <AppLocale>[];
      env.addLocaleListener(observed.add);

      env.setLocale(AppLocale.en);

      expect(env.locale, AppLocale.en);
      expect(observed, <AppLocale>[AppLocale.en]);
    });

    test('setLocale to the SAME locale is a no-op (no listener fired)', () {
      final env = _buildEnvironment(initialLocale: AppLocale.tr);
      final observed = <AppLocale>[];
      env.addLocaleListener(observed.add);

      env.setLocale(AppLocale.tr);

      expect(env.locale, AppLocale.tr);
      expect(observed, isEmpty);
    });

    test('removeLocaleListener stops further notifications', () {
      final env = _buildEnvironment(initialLocale: AppLocale.tr);
      final observed = <AppLocale>[];
      void listener(AppLocale locale) => observed.add(locale);

      env.addLocaleListener(listener);
      env.setLocale(AppLocale.en);
      env.removeLocaleListener(listener);
      env.setLocale(AppLocale.tr);

      // Only the first change was observed.
      expect(observed, <AppLocale>[AppLocale.en]);
    });

    test('toggleLocale cycles through the supported locales', () {
      final env = _buildEnvironment(initialLocale: AppLocale.tr);
      final observed = <AppLocale>[];
      env.addLocaleListener(observed.add);

      env.toggleLocale();
      expect(env.locale, AppLocale.en);
      env.toggleLocale();
      // Wraps back to the first supported locale.
      expect(env.locale, AppLocale.tr);

      expect(observed, <AppLocale>[AppLocale.en, AppLocale.tr]);
    });

    test('toggleLocale is a no-op when only one locale is supported', () {
      final env = _buildEnvironment(
        initialLocale: AppLocale.en,
        supportedLocales: const <AppLocale>[AppLocale.en],
      );
      final observed = <AppLocale>[];
      env.addLocaleListener(observed.add);

      env.toggleLocale();

      // index 0 → (0+1)%1 == 0 → same locale → setLocale no-ops.
      expect(env.locale, AppLocale.en);
      expect(observed, isEmpty);
    });

    test('multiple listeners all receive the change', () {
      final env = _buildEnvironment(initialLocale: AppLocale.tr);
      final a = <AppLocale>[];
      final b = <AppLocale>[];
      env.addLocaleListener(a.add);
      env.addLocaleListener(b.add);

      env.setLocale(AppLocale.en);

      expect(a, <AppLocale>[AppLocale.en]);
      expect(b, <AppLocale>[AppLocale.en]);
    });

    test('default services are wired (palette/progress/prompt parsers)', () {
      // The optional constructor parameters default to real, non-null
      // instances — the environment is usable without explicit wiring.
      final env = _buildEnvironment();
      expect(env.paletteSuggestionService, isNotNull);
      expect(env.progressParser, isNotNull);
      expect(env.promptParser, isNotNull);
      expect(env.dryRun, isFalse);
    });
  });
}
