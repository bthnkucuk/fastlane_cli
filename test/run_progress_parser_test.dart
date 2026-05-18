import 'package:fastlane_cli/src/services/run_progress_parser.dart';
import 'package:test/test.dart';

void main() {
  group('RunProgressParser', () {
    const parser = RunProgressParser();

    test('parses writing line as active file', () {
      final result = parser.parse(
        'Writing to fastlane/android/metadata/en-US/title.txt...',
      );

      expect(result, isNotNull);
      expect(result!.activeFile, 'fastlane/android/metadata/en-US/title.txt');
      expect(result.indeterminate, isTrue);
    });

    test('parses downloaded line as active file', () {
      final result = parser.parse(
        'Downloaded - fastlane/ios/screenshots/en-US/01.png',
      );

      expect(result, isNotNull);
      expect(result!.activeFile, 'fastlane/ios/screenshots/en-US/01.png');
      expect(result.indeterminate, isTrue);
    });

    test('parses percentage as determinate progress', () {
      final result = parser.parse('Syncing assets... 42%');

      expect(result, isNotNull);
      expect(result!.progressValue, closeTo(0.42, 0.0001));
      expect(result.indeterminate, isFalse);
    });

    test('parses fraction as determinate progress', () {
      final result = parser.parse('Downloading screenshots (3/12)');

      expect(result, isNotNull);
      expect(result!.progressValue, closeTo(0.25, 0.0001));
      expect(result.indeterminate, isFalse);
    });

    test('returns null when no progress signal exists', () {
      final result = parser.parse('Everything is okay');

      expect(result, isNull);
    });

    test('parses App Store screenshot download line', () {
      final result = parser.parse(
        "Downloading existing screenshot 'en-US/01.png' for language",
      );

      expect(result, isNotNull);
      expect(result!.activeFile, 'en-US/01.png');
    });

    test('parses generic Downloading line', () {
      final result = parser.parse('Downloading fastlane/metadata');

      expect(result, isNotNull);
      expect(result!.activeFile, 'fastlane/metadata');
    });
  });
}
