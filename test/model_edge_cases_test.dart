import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/model/guide_topic.dart';
import 'package:test/test.dart';

void main() {
  group('CliCategory', () {
    test('descriptionFor returns empty when no descriptions', () {
      final category = CliCategory(
        id: 'c',
        title: const <LocaleCode, String>{LocaleCode.en: 'T'},
        description: const <LocaleCode, String>{},
        actionIds: const <String>[],
      );
      expect(category.descriptionFor(LocaleCode.en), '');
    });

    test('titleFor falls back when locale missing', () {
      final category = CliCategory(
        id: 'c',
        title: const <LocaleCode, String>{LocaleCode.tr: 'TR'},
        description: const <LocaleCode, String>{LocaleCode.tr: 'D'},
        actionIds: const <String>[],
      );
      expect(category.titleFor(LocaleCode.en), 'TR');
    });
  });

  group('GuideTopic', () {
    test('accessors fall back across locales', () {
      const topic = GuideTopic(
        id: 't',
        title: <LocaleCode, String>{LocaleCode.tr: 'T'},
        summary: <LocaleCode, String>{LocaleCode.tr: 'S'},
        checklist: <LocaleCode, List<String>>{
          LocaleCode.tr: <String>['a'],
        },
        paths: <LocaleCode, List<String>>{
          LocaleCode.tr: <String>['p'],
        },
      );

      expect(topic.titleFor(LocaleCode.en), 'T');
      expect(topic.summaryFor(LocaleCode.en), 'S');
      expect(topic.checklistFor(LocaleCode.en), <String>['a']);
      expect(topic.pathsFor(LocaleCode.en), <String>['p']);
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
