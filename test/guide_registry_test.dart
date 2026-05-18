import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/guide_registry.dart';
import 'package:test/test.dart';

import 'support/profile_factory.dart';

void main() {
  group('GuideRegistry', () {
    test('returns null for unknown topic id', () {
      const registry = GuideRegistry();
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      expect(registry.topicById(topicId: 'unknown', profile: profile), isNull);
    });

    test('returns android metadata topic with paths', () {
      const registry = GuideRegistry();
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      final topic = registry.topicById(topicId: 'android_metadata', profile: profile);

      expect(topic, isNotNull);
      final checklist = topic!.checklistFor(LocaleCode.en);
      expect(checklist, hasLength(5));
      expect(checklist.first, contains('locale directory'));
      expect(checklist, contains('Add at least one .png/.jpg screenshot.'));
      final paths = topic.pathsFor(LocaleCode.en);
      expect(paths.first, contains('fastlane'));
      expect(paths.first, endsWith('title.txt'));
    });

    test('returns iOS metadata topic with paths', () {
      const registry = GuideRegistry();
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      final topic = registry.topicById(topicId: 'ios_metadata', profile: profile);

      expect(topic, isNotNull);
      expect(topic!.summaryFor(LocaleCode.en), contains('App Store'));
      final paths = topic.pathsFor(LocaleCode.en);
      // iOS topic surfaces BOTH metadata and screenshots roots — assert each
      // is present rather than a weak `.any(contains('screenshots'))`.
      expect(paths.where((p) => p.contains('metadata')), isNotEmpty);
      expect(paths.where((p) => p.contains('screenshots')), isNotEmpty);
    });
  });
}
