import 'package:fastlane_cli/src/services/run_prompt_parser.dart';
import 'package:test/test.dart';

void main() {
  group('RunPromptParser', () {
    final parser = RunPromptParser();

    group('twoFactorCode', () {
      test('detects the canonical Apple 6-digit prompt', () {
        // The exact log line that motivated this PR.
        const line = '[03:26:55]: Please enter the 6 digit code you '
            'received at +10000000000:';
        final prompt = parser.parse(line);
        expect(prompt, isNotNull);
        expect(prompt!.kind, RunPromptKind.twoFactorCode);
        expect(prompt.maxLength, 6);
      });

      test('validator rejects wrong length', () {
        final prompt = parser
            .parse('[xx]: Please enter the 6 digit code received at +1...')!;
        expect(prompt.validator('123'), isNotNull);
        expect(prompt.validator('1234567'), isNotNull);
      });

      test('validator rejects non-digit characters', () {
        final prompt = parser
            .parse('[xx]: Please enter the 6 digit code received at +1...')!;
        expect(prompt.validator('abcdef'), isNotNull);
      });

      test('validator accepts exact-length numeric code', () {
        final prompt = parser
            .parse('[xx]: Please enter the 6 digit code received at +1...')!;
        expect(prompt.validator('123456'), isNull);
      });

      test('honours non-default digit count', () {
        final prompt = parser
            .parse('Please enter the 4 digit code we just sent:')!;
        expect(prompt.maxLength, 4);
        expect(prompt.validator('1234'), isNull);
        expect(prompt.validator('12345'), isNotNull);
      });
    });

    group('yesNo', () {
      test('matches (y/n)', () {
        final prompt = parser.parse('Continue? (y/n)');
        expect(prompt, isNotNull);
        expect(prompt!.kind, RunPromptKind.yesNo);
      });

      test('matches [Y/n]', () {
        final prompt = parser.parse('Continue? [Y/n]');
        expect(prompt, isNotNull);
        expect(prompt!.kind, RunPromptKind.yesNo);
      });

      test('matches [y/N]', () {
        final prompt = parser.parse('Continue? [y/N]');
        expect(prompt, isNotNull);
        expect(prompt!.kind, RunPromptKind.yesNo);
      });

      test('validator accepts y/yes/n/no, rejects other input', () {
        final prompt = parser.parse('Continue? (y/n)')!;
        expect(prompt.validator('y'), isNull);
        expect(prompt.validator('YES'), isNull);
        expect(prompt.validator('n'), isNull);
        expect(prompt.validator('No'), isNull);
        expect(prompt.validator('maybe'), isNotNull);
        expect(prompt.validator(''), isNotNull);
      });
    });

    group('trustComputer', () {
      test('detects Apple wording', () {
        final prompt =
            parser.parse('Do you want to trust this computer? (y/n)');
        expect(prompt, isNotNull);
        // Trust matcher wins regardless of the trailing y/n.
        expect(prompt!.kind, RunPromptKind.trustComputer);
        expect(prompt.validator('y'), isNull);
        expect(prompt.validator('?'), isNotNull);
      });
    });

    group('chooseIndex', () {
      test('captures the range', () {
        final prompt = parser.parse('Please choose: 1 - 5');
        expect(prompt, isNotNull);
        expect(prompt!.kind, RunPromptKind.chooseIndex);
      });

      test('validator accepts numbers in range', () {
        final prompt = parser.parse('Please choose: 1 - 3')!;
        expect(prompt.validator('1'), isNull);
        expect(prompt.validator('3'), isNull);
        expect(prompt.validator('0'), isNotNull);
        expect(prompt.validator('4'), isNotNull);
        expect(prompt.validator('abc'), isNotNull);
      });
    });

    group('freeForm fallback', () {
      test('matches a question-style line ending with colon', () {
        final prompt =
            parser.parse('Please type your App Store team name:');
        expect(prompt, isNotNull);
        expect(prompt!.kind, RunPromptKind.freeForm);
        expect(prompt.validator(''), isNotNull);
        expect(prompt.validator('Acme Inc'), isNull);
      });

      test('does not match log lines that start with a timestamp', () {
        // fastlane log lines starting with `[hh:mm:ss]:` should not be
        // surfaced as a free-form prompt — but the 2FA matcher will still
        // pick them up if the rest of the line matches.
        final prompt = parser.parse('[03:26:55]: Just a status update.');
        expect(prompt, isNull);
      });

      test('returns null for plain log output', () {
        expect(parser.parse('Building app...'), isNull);
        expect(parser.parse(''), isNull);
        expect(parser.parse('  '), isNull);
      });
    });

    test('validation-error withValidationError preserves other fields', () {
      final prompt = parser.parse('Continue? (y/n)')!;
      final updated = prompt.withValidationError('bad');
      expect(updated.kind, prompt.kind);
      expect(updated.label, prompt.label);
      expect(updated.validationError, 'bad');
    });
  });
}
