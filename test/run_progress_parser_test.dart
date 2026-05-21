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

    test('clamps an over-100% percentage to 1.0', () {
      final result = parser.parse('Uploading 150% complete');

      expect(result, isNotNull);
      expect(result!.progressValue, 1.0);
      expect(result.indeterminate, isFalse);
    });

    test('parses a fractional percentage value', () {
      final result = parser.parse('Progress 12.5%');

      expect(result, isNotNull);
      expect(result!.progressValue, closeTo(0.125, 0.0001));
    });

    test('percentage takes precedence over a fraction on the same line', () {
      // Both `90%` and `(1/2)` appear; the percentage branch is checked first.
      final result = parser.parse('Step (1/2) — 90% done');

      expect(result, isNotNull);
      expect(result!.progressValue, closeTo(0.90, 0.0001));
    });

    test('ignores a fraction whose total is zero', () {
      // total == 0 must not divide-by-zero; it falls through to other
      // matchers and ultimately returns null for a non-progress line.
      final result = parser.parse('Weird (3/0) marker');

      expect(result, isNull);
    });

    test('writing matcher is anchored to end-of-line', () {
      // `Writing to X...` must end the line — trailing text breaks the match.
      final matched = parser.parse('Writing to a/b.txt...');
      expect(matched, isNotNull);
      expect(matched!.activeFile, 'a/b.txt');

      final notMatched = parser.parse('Writing to a/b.txt... and more text');
      expect(notMatched, isNull);
    });

    test('returns null for an empty line', () {
      expect(parser.parse(''), isNull);
    });
  });
}
