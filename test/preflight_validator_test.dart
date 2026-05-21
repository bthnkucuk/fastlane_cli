import 'dart:io';

import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/profile_factory.dart';

void main() {
  group('PreflightValidator', () {
    test('passes android metadata when required files exist', () async {
      final temp = await Directory.systemTemp.createTemp('fastlane_cli_android_ok');
      addTearDown(() => temp.delete(recursive: true));

      final localeDir = Directory(p.join(temp.path, 'fastlane', 'android', 'metadata', 'en-US'))
        ..createSync(recursive: true);
      _write(localeDir.path, 'title.txt');
      _write(localeDir.path, 'short_description.txt');
      _write(localeDir.path, 'full_description.txt');

      for (final dirName in <String>[
        'phoneScreenshots',
        'sevenInchScreenshots',
        'tenInchScreenshots',
        'tvScreenshots',
        'wearScreenshots',
      ]) {
        Directory(p.join(localeDir.path, 'images', dirName)).createSync(recursive: true);
      }
      File(p.join(localeDir.path, 'images', 'phoneScreenshots', '01.png')).writeAsStringSync('fake');

      final action = makeFastlaneAction(
        id: 'android_update_metadata',
        categoryId: 'android',
        lane: 'update_metadata',
        platform: 'android',
        preflightChecks: const <PreflightCheck>[PreflightCheck.androidMetadata],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>[action.id]),
        ],
      );

      final validator = const PreflightValidator();
      final result = validator.validate(profile: profile, action: action);

      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
    });

    test('fails iOS metadata when folders are missing', () async {
      final temp = await Directory.systemTemp.createTemp('fastlane_cli_ios_fail');
      addTearDown(() => temp.delete(recursive: true));

      final action = makeFastlaneAction(
        id: 'ios_update_metadata',
        categoryId: 'ios',
        lane: 'update_metadata',
        platform: 'ios',
        preflightChecks: const <PreflightCheck>[PreflightCheck.iosMetadata],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'ios', actionIds: <String>[action.id]),
        ],
      );

      final validator = const PreflightValidator();
      final result = validator.validate(profile: profile, action: action);

      expect(result.success, isFalse);
      expect(result.guideTopic, PreflightCheck.iosMetadata.value);
      // Hata mesajları sadece var olmasın — eksik metadata yolundan bahsetsin
      // ki kullanıcı doğrudan ne eksik olduğunu görsün.
      expect(result.errors, isNotEmpty);
      expect(
        result.errors.join('\n'),
        anyOf(contains('metadata'), contains('ios')),
        reason: 'iOS metadata preflight hatası metadata/ios bağlamını yansıtmalı',
      );
    });

    test('passes android metadata text-only when txt files exist', () async {
      final temp = await Directory.systemTemp.createTemp('fastlane_cli_android_text');
      addTearDown(() => temp.delete(recursive: true));

      final localeDir = Directory(p.join(temp.path, 'fastlane', 'android', 'metadata', 'en-US'))
        ..createSync(recursive: true);
      _write(localeDir.path, 'title.txt');
      _write(localeDir.path, 'short_description.txt');
      _write(localeDir.path, 'full_description.txt');

      final action = makeFastlaneAction(
        id: 'android_text',
        categoryId: 'android',
        lane: 'lane',
        platform: 'android',
        preflightChecks: const <PreflightCheck>[PreflightCheck.androidMetadataTextOnly],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>[action.id]),
        ],
      );

      final result = const PreflightValidator().validate(profile: profile, action: action);

      expect(result.success, isTrue);
    });

    test('fails android metadata when a required text file is missing', () async {
      final temp = await Directory.systemTemp.createTemp('fastlane_cli_android_partial');
      addTearDown(() => temp.delete(recursive: true));

      final localeDir = Directory(p.join(temp.path, 'fastlane', 'android', 'metadata', 'en-US'))
        ..createSync(recursive: true);
      _write(localeDir.path, 'title.txt');
      _write(localeDir.path, 'short_description.txt');

      final action = makeFastlaneAction(
        id: 'android_partial',
        categoryId: 'android',
        lane: 'lane',
        platform: 'android',
        preflightChecks: const <PreflightCheck>[PreflightCheck.androidMetadata],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>[action.id]),
        ],
      );

      final result = const PreflightValidator().validate(profile: profile, action: action);

      expect(result.success, isFalse);
      expect(result.errors.any((e) => e.contains('full_description')), isTrue);
    });

    test('returns success immediately when the action has no preflight checks',
        () async {
      final action = makeFastlaneAction(
        id: 'no_checks',
        categoryId: 'general',
        lane: 'lane',
      );
      final profile = createTestProfile(
        appRootPath: '/tmp/whatever',
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      final result = const PreflightValidator().validate(
        profile: profile,
        action: action,
      );

      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
      expect(result.guideTopic, isNull);
    });

    test('fails when the android metadata root directory is missing entirely',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('fastlane_cli_android_noroot');
      addTearDown(() => temp.delete(recursive: true));

      final action = makeFastlaneAction(
        id: 'android_noroot',
        categoryId: 'android',
        lane: 'lane',
        platform: 'android',
        preflightChecks: const <PreflightCheck>[PreflightCheck.androidMetadata],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>[action.id]),
        ],
      );

      final result = const PreflightValidator().validate(
        profile: profile,
        action: action,
      );

      expect(result.success, isFalse);
      expect(result.guideTopic, PreflightCheck.androidMetadata.value);
      expect(
        result.errors.any((e) => e.contains('metadata klasörü eksik')),
        isTrue,
      );
      // The checklist is always populated so the user knows what to create.
      expect(result.checklist, isNotEmpty);
    });

    test('fails when the android metadata root has no locale directories',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('fastlane_cli_android_empty');
      addTearDown(() => temp.delete(recursive: true));
      // Root exists but is empty — no locale subdirectories.
      Directory(p.join(temp.path, 'fastlane', 'android', 'metadata'))
          .createSync(recursive: true);

      final action = makeFastlaneAction(
        id: 'android_empty',
        categoryId: 'android',
        lane: 'lane',
        platform: 'android',
        preflightChecks: const <PreflightCheck>[PreflightCheck.androidMetadata],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>[action.id]),
        ],
      );

      final result = const PreflightValidator().validate(
        profile: profile,
        action: action,
      );

      expect(result.success, isFalse);
      expect(
        result.errors.any((e) => e.contains('locale klasörü bulunamadı')),
        isTrue,
      );
    });

    test('aggregates errors across multiple preflight checks', () async {
      // Two checks, both failing — the validator must merge errors and keep
      // a guide topic from the first failing check.
      final temp =
          await Directory.systemTemp.createTemp('fastlane_cli_multi_check');
      addTearDown(() => temp.delete(recursive: true));

      final action = makeFastlaneAction(
        id: 'multi',
        categoryId: 'general',
        lane: 'lane',
        preflightChecks: const <PreflightCheck>[
          PreflightCheck.androidMetadata,
          PreflightCheck.iosMetadata,
        ],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'general', actionIds: <String>[action.id]),
        ],
      );

      final result = const PreflightValidator().validate(
        profile: profile,
        action: action,
      );

      expect(result.success, isFalse);
      // First failing check wins the guide topic.
      expect(result.guideTopic, PreflightCheck.androidMetadata.value);
      // Errors from BOTH checks are present.
      expect(
        result.errors.any((e) => e.contains('Android')),
        isTrue,
      );
      expect(
        result.errors.any((e) => e.toLowerCase().contains('ios')),
        isTrue,
      );
      // Checklists are merged too.
      expect(result.checklist.length, greaterThan(3));
    });

    test('android text-only fails when the metadata root is missing', () async {
      final temp =
          await Directory.systemTemp.createTemp('fastlane_cli_text_noroot');
      addTearDown(() => temp.delete(recursive: true));

      final action = makeFastlaneAction(
        id: 'text_noroot',
        categoryId: 'android',
        lane: 'lane',
        platform: 'android',
        preflightChecks: const <PreflightCheck>[
          PreflightCheck.androidMetadataTextOnly,
        ],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'android', actionIds: <String>[action.id]),
        ],
      );

      final result = const PreflightValidator().validate(
        profile: profile,
        action: action,
      );

      expect(result.success, isFalse);
      expect(result.guideTopic, PreflightCheck.androidMetadataTextOnly.value);
    });

    test('passes iOS metadata when locale txt and screenshots root exist', () async {
      final temp = await Directory.systemTemp.createTemp('fastlane_cli_ios_ok');
      addTearDown(() => temp.delete(recursive: true));

      Directory(p.join(temp.path, 'fastlane', 'ios', 'metadata', 'en-US')).createSync(recursive: true);
      File(p.join(temp.path, 'fastlane', 'ios', 'metadata', 'en-US', 'title.txt')).writeAsStringSync('t');
      Directory(p.join(temp.path, 'fastlane', 'ios', 'screenshots')).createSync(recursive: true);
      Directory(p.join(temp.path, 'fastlane', 'ios', 'metadata', 'review_information')).createSync(recursive: true);

      final action = makeFastlaneAction(
        id: 'ios_lane',
        categoryId: 'ios',
        lane: 'lane',
        platform: 'ios',
        preflightChecks: const <PreflightCheck>[PreflightCheck.iosMetadata],
      );
      final profile = createTestProfile(
        appRootPath: temp.path,
        actions: <CliAction>[action],
        categories: <CliCategory>[
          makeCategory(id: 'ios', actionIds: <String>[action.id]),
        ],
      );

      final result = const PreflightValidator().validate(profile: profile, action: action);

      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
    });
  });
}

void _write(String directoryPath, String fileName) {
  File(p.join(directoryPath, fileName)).writeAsStringSync('sample');
}
