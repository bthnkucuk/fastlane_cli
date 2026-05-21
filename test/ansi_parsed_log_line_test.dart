import 'package:fastlane_cli/src/ui/ansi_parsed_log_line.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('stripAnsiSequences', () {
    test('removes SGR color codes', () {
      expect(stripAnsiSequences('\x1b[31mhello\x1b[0m'), 'hello');
    });

    test('removes 256-color SGR sequences', () {
      expect(
        stripAnsiSequences('\x1b[38;5;202mwarn\x1b[0m'),
        'warn',
      );
    });

    test('removes truecolor SGR sequences', () {
      expect(
        stripAnsiSequences('\x1b[38;2;10;20;30mrgb\x1b[0m'),
        'rgb',
      );
    });

    test('removes OSC hyperlink sequences (BEL terminator)', () {
      expect(
        stripAnsiSequences('\x1b]8;;https://example.com\x07link\x1b]8;;\x07'),
        'link',
      );
    });

    test('removes OSC hyperlink sequences (ST terminator)', () {
      expect(
        stripAnsiSequences('\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\'),
        'link',
      );
    });

    test('keeps a stray ESC at end of line', () {
      expect(stripAnsiSequences('hi\x1b'), 'hi\x1b');
    });

    test('strips multiple consecutive SGR sequences', () {
      expect(
        stripAnsiSequences('\x1b[1m\x1b[31mbold-red\x1b[0m'),
        'bold-red',
      );
    });
  });

  group('logLineContainsAnsi', () {
    test('detects ESC byte', () {
      expect(logLineContainsAnsi('\x1b[31m'), isTrue);
    });

    test('returns false for plain text', () {
      expect(logLineContainsAnsi('plain log line'), isFalse);
    });
  });

  group('ansiLineToSpan', () {
    const base = TextStyle(color: Colors.white);

    test('plain text is unchanged in plain form', () {
      final span = ansiLineToSpan('hi', baseStyle: base);
      expect(span, isA<TextSpan>());
      final ts = span as TextSpan;
      expect(ts.text, 'hi');
      expect(ts.style?.color, Colors.white);
    });

    test('applies foreground red', () {
      final span = ansiLineToSpan('\x1b[31merr\x1b[0m', baseStyle: base);
      expect(_spanPlainText(span), 'err');
      expect(_findChild(span, text: 'err', color: Colors.red), isNotNull);
    });

    test('applies bright foreground (90-97)', () {
      final span = ansiLineToSpan('\x1b[91mbr\x1b[0m', baseStyle: base);
      expect(_findChild(span, text: 'br', color: Colors.brightRed), isNotNull);
    });

    test('applies bold attribute', () {
      final span = ansiLineToSpan('\x1b[1mbold\x1b[0m', baseStyle: base);
      final hit = _findChild(span, text: 'bold');
      expect(hit?.style?.fontWeight, FontWeight.bold);
    });

    test('applies italic attribute', () {
      final span = ansiLineToSpan('\x1b[3mit\x1b[0m', baseStyle: base);
      final hit = _findChild(span, text: 'it');
      expect(hit?.style?.fontStyle, FontStyle.italic);
    });

    test('truecolor 38;2;r;g;b sets exact color', () {
      final span = ansiLineToSpan(
        '\x1b[38;2;10;20;30mrgb\x1b[0m',
        baseStyle: base,
      );
      final hit = _findChild(span, text: 'rgb');
      expect(hit?.style?.color, Color.fromRGB(10, 20, 30));
    });

    test('256-color 38;5;n maps to a color', () {
      final span = ansiLineToSpan(
        '\x1b[38;5;9mr\x1b[0m',
        baseStyle: base,
      );
      // index 9 = bright red
      final hit = _findChild(span, text: 'r');
      expect(hit?.style?.color, Colors.brightRed);
    });

    test('SGR 24 removes only underline, keeps lineThrough', () {
      // underline + lineThrough, then disable underline only
      final span = ansiLineToSpan(
        '\x1b[4m\x1b[9mboth\x1b[24mafter\x1b[0m',
        baseStyle: base,
      );
      final after = _findChild(span, text: 'after');
      expect(after?.style?.decoration?.hasUnderline, isFalse);
      expect(after?.style?.decoration?.hasLineThrough, isTrue);
    });

    test('SGR 29 removes only lineThrough, keeps underline', () {
      final span = ansiLineToSpan(
        '\x1b[4m\x1b[9mboth\x1b[29mafter\x1b[0m',
        baseStyle: base,
      );
      final after = _findChild(span, text: 'after');
      expect(after?.style?.decoration?.hasUnderline, isTrue);
      expect(after?.style?.decoration?.hasLineThrough, isFalse);
    });

    test('SGR 0 resets to base style', () {
      final span = ansiLineToSpan(
        '\x1b[1;31mhot\x1b[0mcold',
        baseStyle: base,
      );
      final hot = _findChild(span, text: 'hot');
      expect(hot?.style?.color, Colors.red);
      expect(hot?.style?.fontWeight, FontWeight.bold);
      final cold = _findChild(span, text: 'cold');
      expect(cold?.style?.color, Colors.white);
    });

    test('multiple SGR codes in one escape', () {
      final span = ansiLineToSpan('\x1b[1;4;31mx\x1b[0m', baseStyle: base);
      final hit = _findChild(span, text: 'x');
      expect(hit?.style?.color, Colors.red);
      expect(hit?.style?.fontWeight, FontWeight.bold);
      expect(hit?.style?.decoration?.hasUnderline, isTrue);
    });

    test('OSC hyperlinks are stripped from output', () {
      final span = ansiLineToSpan(
        '\x1b]8;;https://example.com\x07click\x1b]8;;\x07',
        baseStyle: base,
      );
      expect(_spanPlainText(span), 'click');
    });

    test('malformed CSI without final byte is emitted as text', () {
      // `\x1b[12;34` has only parameter bytes, no final byte in the
      // 0x40..0x7e range — the parser should fall back to literal output.
      final span = ansiLineToSpan('a\x1b[12;34', baseStyle: base);
      expect(_spanPlainText(span), 'a\x1b[12;34');
    });

    test('empty SGR body (\\x1b[m) acts like reset', () {
      final span = ansiLineToSpan(
        '\x1b[31mred\x1b[mplain',
        baseStyle: base,
      );
      final plain = _findChild(span, text: 'plain');
      expect(plain?.style?.color, Colors.white);
    });
  });
}

String _spanPlainText(InlineSpan span) => span.toPlainText();

TextSpan? _findChild(
  InlineSpan span, {
  required String text,
  Color? color,
}) {
  if (span is TextSpan) {
    final matchesText = span.text == text;
    final matchesColor = color == null || span.style?.color == color;
    if (matchesText && matchesColor) return span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final hit = _findChild(child, text: text, color: color);
      if (hit != null) return hit;
    }
  }
  return null;
}
