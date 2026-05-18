import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/model/guide_topic.dart';
import 'package:test/test.dart';

void main() {
  group('CliCategory', () {
    test('descriptionFor returns empty when no descriptions', () {
      final category = CliCategory(
        id: 'c',
        title: const <AppLocale, String>{AppLocale.en: 'T'},
        description: const <AppLocale, String>{},
        actionIds: const <String>[],
      );
      expect(category.descriptionFor(AppLocale.en), '');
    });

    test('titleFor falls back when locale missing', () {
      final category = CliCategory(
        id: 'c',
        title: const <AppLocale, String>{AppLocale.tr: 'TR'},
        description: const <AppLocale, String>{AppLocale.tr: 'D'},
        actionIds: const <String>[],
      );
      expect(category.titleFor(AppLocale.en), 'TR');
    });
  });

  group('GuideTopic', () {
    test('accessors fall back across locales', () {
      const topic = GuideTopic(
        id: 't',
        title: <AppLocale, String>{AppLocale.tr: 'T'},
        summary: <AppLocale, String>{AppLocale.tr: 'S'},
        checklist: <AppLocale, List<String>>{
          AppLocale.tr: <String>['a'],
        },
        paths: <AppLocale, List<String>>{
          AppLocale.tr: <String>['p'],
        },
      );

      expect(topic.titleFor(AppLocale.en), 'T');
      expect(topic.summaryFor(AppLocale.en), 'S');
      expect(topic.checklistFor(AppLocale.en), <String>['a']);
      expect(topic.pathsFor(AppLocale.en), <String>['p']);
    });
  });

  group('RunSession', () {
    test('copyWith replaces fields', () {
      const initial = RunSession(
        status: RunStatus.running,
        actionId: 'a',
        logs: <RunLogEntry>[RunLogEntry(message: 'm', isError: false)],
      );
      final next = initial.copyWith(
        status: RunStatus.succeeded,
        exitCode: 0,
        progressValue: 1,
        progressIndeterminate: false,
        activeFile: 'f.txt',
        validationErrors: const <String>['e'],
        validationChecklist: const <String>['c'],
      );
      expect(next.status, RunStatus.succeeded);
      expect(next.exitCode, 0);
      expect(next.activeFile, 'f.txt');
      expect(next.validationErrors, <String>['e']);
    });
  });
}
