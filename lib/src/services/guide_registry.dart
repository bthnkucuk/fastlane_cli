import 'package:path/path.dart' as p;

import '../localization/i18n/strings.g.dart';
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

  /// Reads a property from each [AppLocale]'s slang translation bundle and
  /// produces a per-[LocaleCode] map suitable for [GuideTopic].
  Map<LocaleCode, T> _perLocale<T>(T Function(Translations t) read) {
    return <LocaleCode, T>{
      for (final appLocale in AppLocale.values)
        appLocale.toLocaleCode(): read(appLocale.buildSync()),
    };
  }

  GuideTopic _androidMetadata(CliProfile profile) {
    final root = p.join(profile.fastlaneDirectoryPath, 'android', 'metadata');
    final pathSuffixes = const <String>[
      '/<locale>/title.txt',
      '/<locale>/short_description.txt',
      '/<locale>/full_description.txt',
      '/<locale>/changelogs/<version_code>.txt',
      '/<locale>/images/phoneScreenshots',
      '/<locale>/images/sevenInchScreenshots',
      '/<locale>/images/tenInchScreenshots',
      '/<locale>/images/tvScreenshots',
      '/<locale>/images/wearScreenshots',
    ];
    final paths = <String>[for (final s in pathSuffixes) '$root$s'];
    return GuideTopic(
      id: 'android_metadata',
      title: _perLocale((t) => t.guides.androidMetadata.title),
      summary: _perLocale((t) => t.guides.androidMetadata.summary),
      checklist: _perLocale((t) => t.guides.androidMetadata.checklist),
      paths: <LocaleCode, List<String>>{
        for (final code in LocaleCode.values) code: paths,
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
    final basePaths = <String>[
      '$metadataRoot/<locale>/*.txt',
      '$metadataRoot/<locale>/whats_new.txt',
      '$metadataRoot/review_information/contact_email.txt',
      '$metadataRoot/review_information/contact_first_name.txt',
      '$metadataRoot/review_information/contact_last_name.txt',
      '$metadataRoot/review_information/contact_phone.txt',
      '$screenshotsRoot/<locale>/*',
    ];
    return GuideTopic(
      id: 'ios_metadata',
      title: _perLocale((t) => t.guides.iosMetadata.title),
      summary: _perLocale((t) => t.guides.iosMetadata.summary),
      checklist: _perLocale((t) => t.guides.iosMetadata.checklist),
      paths: _perLocale(
        (t) => <String>[
          ...basePaths,
          '$screenshotsRoot${t.guides.iosMetadata.appleTvSuffix}',
          '$screenshotsRoot${t.guides.iosMetadata.iMessageSuffix}',
        ],
      ),
    );
  }
}
