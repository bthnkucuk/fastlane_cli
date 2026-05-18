import 'package:path/path.dart' as p;

import '../localization/locale_code.dart';
import '../model/cli_profile.dart';
import '../model/guide_topic.dart';

class GuideRegistry {
  const GuideRegistry();

  GuideTopic? topicById({
    required String topicId,
    required CliProfile profile,
  }) {
    return switch (topicId) {
      'android_metadata' => _androidMetadata(profile),
      'ios_metadata' => _iosMetadata(profile),
      _ => null,
    };
  }

  GuideTopic _androidMetadata(CliProfile profile) {
    final root = p.join(profile.fastlaneDirectoryPath, 'android', 'metadata');
    return GuideTopic(
      id: 'android_metadata',
      title: const <LocaleCode, String>{
        LocaleCode.tr: 'Android Metadata & Screenshots',
        LocaleCode.en: 'Android Metadata & Screenshots',
      },
      summary: const <LocaleCode, String>{
        LocaleCode.tr:
            'Play Store metadata ve screenshot klasörlerini bu yapıda hazırlayın.',
        LocaleCode.en:
            'Prepare Play Store metadata and screenshot folders in this structure.',
      },
      checklist: const <LocaleCode, List<String>>{
        LocaleCode.tr: <String>[
          'Locale klasörü açın (ör: tr-TR, en-US).',
          'title.txt, short_description.txt, full_description.txt ekleyin.',
          'changelogs/<version_code>.txt ile release notes dosyası ekleyin.',
          'images altında tüm screenshot klasörlerini oluşturun.',
          'En az bir ekran görüntüsünü .png/.jpg olarak ekleyin.',
        ],
        LocaleCode.en: <String>[
          'Create a locale directory (e.g. tr-TR, en-US).',
          'Add title.txt, short_description.txt, full_description.txt.',
          'Add release notes file as changelogs/<version_code>.txt.',
          'Create every screenshot folder under images.',
          'Add at least one .png/.jpg screenshot.',
        ],
      },
      paths: <LocaleCode, List<String>>{
        LocaleCode.tr: <String>[
          '$root/<locale>/title.txt',
          '$root/<locale>/short_description.txt',
          '$root/<locale>/full_description.txt',
          '$root/<locale>/changelogs/<version_code>.txt',
          '$root/<locale>/images/phoneScreenshots',
          '$root/<locale>/images/sevenInchScreenshots',
          '$root/<locale>/images/tenInchScreenshots',
          '$root/<locale>/images/tvScreenshots',
          '$root/<locale>/images/wearScreenshots',
        ],
        LocaleCode.en: <String>[
          '$root/<locale>/title.txt',
          '$root/<locale>/short_description.txt',
          '$root/<locale>/full_description.txt',
          '$root/<locale>/changelogs/<version_code>.txt',
          '$root/<locale>/images/phoneScreenshots',
          '$root/<locale>/images/sevenInchScreenshots',
          '$root/<locale>/images/tenInchScreenshots',
          '$root/<locale>/images/tvScreenshots',
          '$root/<locale>/images/wearScreenshots',
        ],
      },
    );
  }

  GuideTopic _iosMetadata(CliProfile profile) {
    final metadataRoot = p.join(
      profile.fastlaneDirectoryPath,
      'ios',
      'metadata',
    );
    final screenshotsRoot = p.join(
      profile.fastlaneDirectoryPath,
      'ios',
      'screenshots',
    );
    return GuideTopic(
      id: 'ios_metadata',
      title: const <LocaleCode, String>{
        LocaleCode.tr: 'iOS Metadata & Screenshots',
        LocaleCode.en: 'iOS Metadata & Screenshots',
      },
      summary: const <LocaleCode, String>{
        LocaleCode.tr:
            'App Store metadata/screenshot yapısını düzeltip sonra aksiyonu tekrar çalıştırın.',
        LocaleCode.en:
            'Fix App Store metadata/screenshot structure, then retry the action.',
      },
      checklist: const <LocaleCode, List<String>>{
        LocaleCode.tr: <String>[
          'Her locale için metadata klasörü oluşturun (ör: tr-TR, en-US).',
          'Locale klasörlerinde .txt metadata ve whats_new.txt dosyalarını ekleyin.',
          'review_information klasörüne iletişim dosyalarını koyun.',
          'screenshots/<locale> altında en az bir screenshot ekleyin.',
        ],
        LocaleCode.en: <String>[
          'Create locale metadata folders (e.g. tr-TR, en-US).',
          'Add .txt metadata files and whats_new.txt under each locale folder.',
          'Place contact files under review_information.',
          'Add at least one screenshot under screenshots/<locale>.',
        ],
      },
      paths: <LocaleCode, List<String>>{
        LocaleCode.tr: <String>[
          '$metadataRoot/<locale>/*.txt',
          '$metadataRoot/<locale>/whats_new.txt',
          '$metadataRoot/review_information/contact_email.txt',
          '$metadataRoot/review_information/contact_first_name.txt',
          '$metadataRoot/review_information/contact_last_name.txt',
          '$metadataRoot/review_information/contact_phone.txt',
          '$screenshotsRoot/<locale>/*',
          '$screenshotsRoot/appleTV (opsiyonel)',
          '$screenshotsRoot/iMessage (opsiyonel)',
        ],
        LocaleCode.en: <String>[
          '$metadataRoot/<locale>/*.txt',
          '$metadataRoot/<locale>/whats_new.txt',
          '$metadataRoot/review_information/contact_email.txt',
          '$metadataRoot/review_information/contact_first_name.txt',
          '$metadataRoot/review_information/contact_last_name.txt',
          '$metadataRoot/review_information/contact_phone.txt',
          '$screenshotsRoot/<locale>/*',
          '$screenshotsRoot/appleTV (optional)',
          '$screenshotsRoot/iMessage (optional)',
        ],
      },
    );
  }
}
