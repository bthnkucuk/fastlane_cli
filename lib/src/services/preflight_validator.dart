import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/cli_action.dart';
import '../model/cli_profile.dart';
import '../model/preflight_result.dart';

class PreflightValidator {
  const PreflightValidator();

  PreflightResult validate({required CliProfile profile, required CliAction action}) {
    if (action.preflightChecks.isEmpty) {
      return const PreflightResult(success: true);
    }

    final allErrors = <String>[];
    final allChecklist = <String>[];
    String? guideTopic;

    for (final check in action.preflightChecks) {
      final result = switch (check) {
        PreflightCheck.androidMetadata => _validateAndroidMetadata(profile),
        PreflightCheck.androidMetadataTextOnly => _validateAndroidMetadataTextOnly(profile),
        PreflightCheck.iosMetadata => _validateIosMetadata(profile),
      };
      if (!result.success) {
        guideTopic ??= result.guideTopic;
        allErrors.addAll(result.errors);
      }
      allChecklist.addAll(result.checklist);
    }

    if (allErrors.isEmpty) {
      return const PreflightResult(success: true);
    }
    return PreflightResult(success: false, guideTopic: guideTopic, errors: allErrors, checklist: allChecklist);
  }

  PreflightResult _validateAndroidMetadata(CliProfile profile) {
    final metadataRoot = Directory(p.join(profile.fastlaneDirectoryPath, 'android', 'metadata'));

    final errors = <String>[];
    final checklist = <String>[
      'fastlane/android/metadata/<locale>/title.txt',
      'fastlane/android/metadata/<locale>/short_description.txt',
      'fastlane/android/metadata/<locale>/full_description.txt',
      'fastlane/android/metadata/<locale>/changelogs/<version_code>.txt',
      'fastlane/android/metadata/<locale>/images/phoneScreenshots',
      'fastlane/android/metadata/<locale>/images/sevenInchScreenshots',
      'fastlane/android/metadata/<locale>/images/tenInchScreenshots',
      'fastlane/android/metadata/<locale>/images/tvScreenshots',
      'fastlane/android/metadata/<locale>/images/wearScreenshots',
    ];

    if (!metadataRoot.existsSync()) {
      errors.add('Android metadata klasörü eksik: ${metadataRoot.path}');
      return PreflightResult(
        success: false,
        guideTopic: PreflightCheck.androidMetadata.value,
        errors: errors,
        checklist: checklist,
      );
    }

    final localeDirectories = metadataRoot
        .listSync()
        .whereType<Directory>()
        .where((item) => !p.basename(item.path).startsWith('.'))
        .toList();

    if (localeDirectories.isEmpty) {
      errors.add('Android metadata locale klasörü bulunamadı.');
    }

    final requiredMetadataFiles = <String>['title.txt', 'short_description.txt', 'full_description.txt'];
    final requiredScreenshotDirs = <String>[
      'phoneScreenshots',
      'sevenInchScreenshots',
      'tenInchScreenshots',
      'tvScreenshots',
      'wearScreenshots',
    ];

    var hasAnyScreenshot = false;

    for (final localeDir in localeDirectories) {
      for (final file in requiredMetadataFiles) {
        final path = p.join(localeDir.path, file);
        if (!File(path).existsSync()) {
          errors.add('${p.basename(localeDir.path)} locale için dosya eksik: $file');
        }
      }

      final imagesRoot = Directory(p.join(localeDir.path, 'images'));
      if (!imagesRoot.existsSync()) {
        errors.add('${p.basename(localeDir.path)} locale için images klasörü eksik.');
        continue;
      }

      for (final dirName in requiredScreenshotDirs) {
        final screenshotDir = Directory(p.join(imagesRoot.path, dirName));
        if (!screenshotDir.existsSync()) {
          errors.add('${p.basename(localeDir.path)} locale için eksik screenshot klasörü: $dirName');
          continue;
        }
        if (_containsScreenshot(screenshotDir)) {
          hasAnyScreenshot = true;
        }
      }
    }

    if (!hasAnyScreenshot) {
      errors.add('Android screenshot dosyası bulunamadı (.png/.jpg/.jpeg).');
    }

    return PreflightResult(
      success: errors.isEmpty,
      guideTopic: errors.isEmpty ? null : PreflightCheck.androidMetadata.value,
      errors: errors,
      checklist: checklist,
    );
  }

  PreflightResult _validateAndroidMetadataTextOnly(CliProfile profile) {
    final metadataRoot = Directory(p.join(profile.fastlaneDirectoryPath, 'android', 'metadata'));

    final errors = <String>[];
    final checklist = <String>[
      'fastlane/android/metadata/<locale>/title.txt',
      'fastlane/android/metadata/<locale>/short_description.txt',
      'fastlane/android/metadata/<locale>/full_description.txt',
    ];

    if (!metadataRoot.existsSync()) {
      errors.add('Android metadata klasörü eksik: ${metadataRoot.path}');
      return PreflightResult(
        success: false,
        guideTopic: PreflightCheck.androidMetadataTextOnly.value,
        errors: errors,
        checklist: checklist,
      );
    }

    final localeDirectories = metadataRoot
        .listSync()
        .whereType<Directory>()
        .where((item) => !p.basename(item.path).startsWith('.'))
        .toList();

    if (localeDirectories.isEmpty) {
      errors.add('Android metadata locale klasörü bulunamadı.');
    }

    final requiredMetadataFiles = <String>['title.txt', 'short_description.txt', 'full_description.txt'];

    for (final localeDir in localeDirectories) {
      for (final file in requiredMetadataFiles) {
        final path = p.join(localeDir.path, file);
        if (!File(path).existsSync()) {
          errors.add('${p.basename(localeDir.path)} locale için dosya eksik: $file');
        }
      }
    }

    return PreflightResult(
      success: errors.isEmpty,
      guideTopic: errors.isEmpty ? null : PreflightCheck.androidMetadataTextOnly.value,
      errors: errors,
      checklist: checklist,
    );
  }

  PreflightResult _validateIosMetadata(CliProfile profile) {
    final metadataRoot = Directory(p.join(profile.fastlaneDirectoryPath, 'ios', 'metadata'));
    final screenshotsRoot = Directory(p.join(profile.fastlaneDirectoryPath, 'ios', 'screenshots'));

    final errors = <String>[];
    final checklist = <String>[
      'fastlane/ios/metadata/<locale>/*.txt',
      'fastlane/ios/metadata/<locale>/whats_new.txt',
      'fastlane/ios/metadata/review_information/*',
      'fastlane/ios/screenshots/<locale>/*',
      'fastlane/ios/screenshots/appleTV (opsiyonel)',
      'fastlane/ios/screenshots/iMessage (opsiyonel)',
    ];

    if (!metadataRoot.existsSync()) {
      errors.add('iOS metadata klasörü eksik: ${metadataRoot.path}');
    }

    final localeDirectories = metadataRoot.existsSync()
        ? metadataRoot.listSync().whereType<Directory>().where((item) {
            final name = p.basename(item.path);
            return name != 'review_information' && !name.startsWith('.');
          }).toList()
        : <Directory>[];

    if (localeDirectories.isEmpty) {
      errors.add('iOS metadata locale klasörü bulunamadı.');
    }

    for (final localeDir in localeDirectories) {
      final txtFiles = localeDir.listSync().whereType<File>().where((file) => file.path.endsWith('.txt')).toList();
      if (txtFiles.isEmpty) {
        errors.add('${p.basename(localeDir.path)} locale klasöründe .txt metadata bulunamadı.');
      }
    }

    final reviewDir = Directory(p.join(metadataRoot.path, 'review_information'));
    if (!reviewDir.existsSync()) {
      // errors.add('iOS review_information klasörü eksik.');
    } else {
      final requiredReviewFiles = <String>[
        'contact_email.txt',
        'contact_first_name.txt',
        'contact_last_name.txt',
        'contact_phone.txt',
      ];
      for (final file in requiredReviewFiles) {
        if (!File(p.join(reviewDir.path, file)).existsSync()) {
          // errors.add('iOS review_information dosyası eksik: $file');
        }
      }
    }

    if (!screenshotsRoot.existsSync()) {
      errors.add('iOS screenshots klasörü eksik: ${screenshotsRoot.path}');
    } else {
      final localeScreenshotDirs = screenshotsRoot.listSync().whereType<Directory>().where((item) {
        final name = p.basename(item.path);
        return name != 'appleTV' && name != 'iMessage' && !name.startsWith('.');
      }).toList();

      if (localeScreenshotDirs.isEmpty) {
        // errors.add('iOS screenshots locale klasörü bulunamadı.');
      }

      var hasAnyScreenshot = false;
      for (final screenshotDir in localeScreenshotDirs) {
        if (_containsScreenshot(screenshotDir)) {
          hasAnyScreenshot = true;
        }
      }

      if (!hasAnyScreenshot) {
        // errors.add('iOS screenshot dosyası bulunamadı (.png/.jpg/.jpeg).');
      }
    }

    return PreflightResult(
      success: errors.isEmpty,
      guideTopic: errors.isEmpty ? null : PreflightCheck.iosMetadata.value,
      errors: errors,
      checklist: checklist,
    );
  }

  bool _containsScreenshot(Directory directory) {
    final entities = directory.listSync(recursive: true);
    for (final entity in entities.whereType<File>()) {
      final extension = p.extension(entity.path).toLowerCase();
      if (extension == '.png' || extension == '.jpg' || extension == '.jpeg') {
        return true;
      }
    }
    return false;
  }
}
