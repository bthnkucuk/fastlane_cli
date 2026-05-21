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
      final checklist = topic!.checklistFor(AppLocale.en);
      expect(checklist, hasLength(5));
      expect(checklist.first, contains('locale directory'));
      expect(checklist, contains('Add at least one .png/.jpg screenshot.'));
      final paths = topic.pathsFor(AppLocale.en);
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
      expect(topic!.summaryFor(AppLocale.en), contains('App Store'));
      final paths = topic.pathsFor(AppLocale.en);
      // iOS topic surfaces BOTH metadata and screenshots roots — assert each
      // is present rather than a weak `.any(contains('screenshots'))`.
      expect(paths.where((p) => p.contains('metadata')), isNotEmpty);
      expect(paths.where((p) => p.contains('screenshots')), isNotEmpty);
    });

    test('android topic populates every AppLocale (no missing locale)', () {
      const registry = GuideRegistry();
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      final topic =
          registry.topicById(topicId: 'android_metadata', profile: profile)!;

      // Every generated locale must have a non-empty title/summary/checklist
      // and paths — the `_perLocale` helper iterates AppLocale.values.
      for (final locale in AppLocale.values) {
        expect(topic.titleFor(locale), isNotEmpty,
            reason: 'android title missing for $locale');
        expect(topic.summaryFor(locale), isNotEmpty,
            reason: 'android summary missing for $locale');
        expect(topic.checklistFor(locale), isNotEmpty,
            reason: 'android checklist missing for $locale');
        expect(topic.pathsFor(locale), isNotEmpty,
            reason: 'android paths missing for $locale');
      }
    });

    test('iOS topic appends locale-specific Apple TV / iMessage suffixes', () {
      const registry = GuideRegistry();
      final profile = createTestProfile(
        appRootPath: '/tmp/app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      final topic =
          registry.topicById(topicId: 'ios_metadata', profile: profile)!;

      // The iOS topic builds paths per-locale (the appleTV/iMessage suffixes
      // are slang-localized). Both locales must carry the same base count
      // plus the two suffixed entries.
      for (final locale in AppLocale.values) {
        final paths = topic.pathsFor(locale);
        // 7 base paths + appleTV suffix + iMessage suffix.
        expect(paths, hasLength(9), reason: 'iOS path count wrong for $locale');
      }
    });

    test('android topic uses the profile fastlane directory in its paths', () {
      const registry = GuideRegistry();
      final profile = createTestProfile(
        appRootPath: '/tmp/custom-app',
        actions: const <CliAction>[],
        categories: const <CliCategory>[],
      );

      final topic =
          registry.topicById(topicId: 'android_metadata', profile: profile)!;
      final paths = topic.pathsFor(AppLocale.en);

      // Paths are anchored under the profile's fastlane directory.
      expect(
        paths.every((p) => p.contains('/tmp/custom-app')),
        isTrue,
      );
    });
  });
}
