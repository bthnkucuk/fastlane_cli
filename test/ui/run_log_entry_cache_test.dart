import 'package:fastlane_cli/src/model/run_session.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('RunLogEntry.parsedAnsi caching', () {
    test('repeated parse with the same baseStyle is memoised', () {
      final entry = RunLogEntry(
        message: '\x1b[31mhello\x1b[0m world',
        isError: false,
      );
      const base = TextStyle(color: Colors.white);

      expect(entry.debugParseCount, 0);
      final first = entry.parsedAnsi(baseStyle: base);
      expect(entry.debugParseCount, 1);

      // Calling again with the same base should NOT re-run the parser.
      final second = entry.parsedAnsi(baseStyle: base);
      expect(entry.debugParseCount, 1);
      expect(identical(first, second), isTrue,
          reason: 'expected cached InlineSpan to be reused');

      // Many subsequent reads stay cheap.
      for (var i = 0; i < 50; i++) {
        entry.parsedAnsi(baseStyle: base);
      }
      expect(entry.debugParseCount, 1);
    });

    test('different baseStyle invalidates the cache', () {
      final entry = RunLogEntry(
        message: '\x1b[31merr\x1b[0m',
        isError: true,
      );
      const base1 = TextStyle(color: Colors.white);
      const base2 = TextStyle(color: Colors.green);

      entry.parsedAnsi(baseStyle: base1);
      entry.parsedAnsi(baseStyle: base2);
      expect(entry.debugParseCount, 2);
      // Reverting to the first style now re-parses (single-slot cache).
      entry.parsedAnsi(baseStyle: base1);
      expect(entry.debugParseCount, 3);
    });

    test('plain (non-ANSI) lines still memoise', () {
      final entry = RunLogEntry(message: 'plain text', isError: false);
      const base = TextStyle(color: Colors.white);
      final a = entry.parsedAnsi(baseStyle: base);
      final b = entry.parsedAnsi(baseStyle: base);
      expect(entry.debugParseCount, 1);
      expect(identical(a, b), isTrue);
    });
  });
}
