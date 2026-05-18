import 'package:nocterm/nocterm.dart';

/// Removes CSI and OSC escape sequences (colors, cursor moves, links).
String stripAnsiSequences(String input) {
  final buf = StringBuffer();
  var i = 0;
  while (i < input.length) {
    if (i < input.length - 1 && input.codeUnitAt(i) == 0x1b) {
      final next = input.codeUnitAt(i + 1);
      if (next == 0x5b) {
        final end = _csiEnd(input, i + 2);
        if (end != -1) {
          i = end;
          continue;
        }
      } else if (next == 0x5d) {
        final end = _oscEnd(input, i + 2);
        if (end != -1) {
          i = end;
          continue;
        }
      }
    }
    buf.writeCharCode(input.codeUnitAt(i));
    i++;
  }
  return buf.toString();
}

bool logLineContainsAnsi(String input) => input.contains('\x1b');

/// Builds a [TextSpan] tree from a line that may contain ANSI SGR (`\x1b[…m`).
InlineSpan ansiLineToSpan(String input, {required TextStyle baseStyle}) {
  if (!logLineContainsAnsi(input)) {
    return TextSpan(text: input, style: baseStyle);
  }

  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  var style = baseStyle;
  var i = 0;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: style));
    buffer.clear();
  }

  while (i < input.length) {
    if (i < input.length - 1 &&
        input.codeUnitAt(i) == 0x1b &&
        input.codeUnitAt(i + 1) == 0x5b) {
      final end = _csiEnd(input, i + 2);
      if (end == -1) {
        buffer.writeCharCode(input.codeUnitAt(i));
        i++;
        continue;
      }
      flush();
      final body = input.substring(i + 2, end - 1);
      if (input.codeUnitAt(end - 1) == 0x6d) {
        style = _applySgrBody(body, style, baseStyle);
      }
      i = end;
      continue;
    }
    if (i < input.length - 1 &&
        input.codeUnitAt(i) == 0x1b &&
        input.codeUnitAt(i + 1) == 0x5d) {
      final end = _oscEnd(input, i + 2);
      if (end != -1) {
        i = end;
        continue;
      }
    }
    buffer.writeCharCode(input.codeUnitAt(i));
    i++;
  }
  flush();

  if (spans.isEmpty) return TextSpan(text: '', style: baseStyle);
  if (spans.length == 1) return spans.single;
  return TextSpan(children: spans);
}

int _csiEnd(String input, int startAfterBracket) {
  for (var j = startAfterBracket; j < input.length; j++) {
    final u = input.codeUnitAt(j);
    if (u >= 0x40 && u <= 0x7e) return j + 1;
  }
  return -1;
}

int _oscEnd(String input, int start) {
  for (var j = start; j < input.length; j++) {
    final u = input.codeUnitAt(j);
    if (u == 0x07) return j + 1;
    if (u == 0x1b && j + 1 < input.length && input.codeUnitAt(j + 1) == 0x5c) {
      return j + 2;
    }
  }
  return -1;
}

TextStyle _applySgrBody(String body, TextStyle current, TextStyle base) {
  final codes = body.isEmpty
      ? <int>[0]
      : body.split(';').map((s) {
          if (s.isEmpty) return 0;
          return int.tryParse(s) ?? 0;
        }).toList();

  var s = current;
  for (var i = 0; i < codes.length; i++) {
    final n = codes[i];
    if (n == 0) {
      s = base;
    } else if (n == 1) {
      s = s.copyWith(fontWeight: FontWeight.bold);
    } else if (n == 2) {
      s = s.copyWith(fontWeight: FontWeight.dim);
    } else if (n == 22) {
      s = s.copyWith(fontWeight: base.fontWeight);
    } else if (n == 3) {
      s = s.copyWith(fontStyle: FontStyle.italic);
    } else if (n == 23) {
      s = s.copyWith(fontStyle: base.fontStyle);
    } else if (n == 4) {
      s = s.copyWith(decoration: _addDecoration(s.decoration, TextDecoration.underline));
    } else if (n == 24) {
      s = s.copyWith(decoration: _removeDecoration(s.decoration, TextDecoration.underline));
    } else if (n == 7) {
      s = s.copyWith(reverse: true);
    } else if (n == 27) {
      s = s.copyWith(reverse: base.reverse);
    } else if (n == 9) {
      s = s.copyWith(decoration: _addDecoration(s.decoration, TextDecoration.lineThrough));
    } else if (n == 29) {
      s = s.copyWith(decoration: _removeDecoration(s.decoration, TextDecoration.lineThrough));
    } else if (n == 39) {
      s = s.copyWith(color: base.color);
    } else if (n == 49) {
      s = s.copyWith(backgroundColor: base.backgroundColor);
    } else if (n == 38) {
      final consumed = _consumeExtendedColor(codes, i, isFg: true, style: s);
      if (consumed != null) {
        s = consumed.$1;
        i = consumed.$2;
      }
    } else if (n == 48) {
      final consumed = _consumeExtendedColor(codes, i, isFg: false, style: s);
      if (consumed != null) {
        s = consumed.$1;
        i = consumed.$2;
      }
    } else if (n >= 30 && n <= 37) {
      s = s.copyWith(color: _ansiFg8(n - 30, bright: false));
    } else if (n >= 90 && n <= 97) {
      s = s.copyWith(color: _ansiFg8(n - 90, bright: true));
    } else if (n >= 40 && n <= 47) {
      s = s.copyWith(backgroundColor: _ansiFg8(n - 40, bright: false));
    } else if (n >= 100 && n <= 107) {
      s = s.copyWith(backgroundColor: _ansiFg8(n - 100, bright: true));
    }
  }
  return s;
}

(TextStyle, int)? _consumeExtendedColor(
  List<int> codes,
  int i, {
  required bool isFg,
  required TextStyle style,
}) {
  if (i + 2 >= codes.length) return null;
  final mode = codes[i + 1];
  if (mode == 5) {
    final c = _ansi256ToColor(codes[i + 2]);
    return (
      isFg ? style.copyWith(color: c) : style.copyWith(backgroundColor: c),
      i + 2,
    );
  }
  if (mode == 2 && i + 4 < codes.length) {
    final c = Color.fromRGB(codes[i + 2], codes[i + 3], codes[i + 4]);
    return (
      isFg ? style.copyWith(color: c) : style.copyWith(backgroundColor: c),
      i + 4,
    );
  }
  return null;
}

TextDecoration _addDecoration(TextDecoration? current, TextDecoration add) {
  final parts = <TextDecoration>[];
  if (current != null) {
    if (current.hasUnderline) parts.add(TextDecoration.underline);
    if (current.hasLineThrough) parts.add(TextDecoration.lineThrough);
    if (current.hasOverline) parts.add(TextDecoration.overline);
  }
  if (!parts.contains(add)) parts.add(add);
  if (parts.isEmpty) return TextDecoration.none;
  if (parts.length == 1) return parts.single;
  return TextDecoration.combine(parts);
}

TextDecoration _removeDecoration(TextDecoration? current, TextDecoration remove) {
  if (current == null) return TextDecoration.none;
  final parts = <TextDecoration>[];
  if (current.hasUnderline && remove != TextDecoration.underline) {
    parts.add(TextDecoration.underline);
  }
  if (current.hasLineThrough && remove != TextDecoration.lineThrough) {
    parts.add(TextDecoration.lineThrough);
  }
  if (current.hasOverline && remove != TextDecoration.overline) {
    parts.add(TextDecoration.overline);
  }
  if (parts.isEmpty) return TextDecoration.none;
  if (parts.length == 1) return parts.single;
  return TextDecoration.combine(parts);
}

Color _ansiFg8(int i, {required bool bright}) {
  const normal = <Color>[
    Colors.black,
    Colors.red,
    Colors.green,
    Colors.yellow,
    Colors.blue,
    Colors.magenta,
    Colors.cyan,
    Colors.white,
  ];
  const brightPal = <Color>[
    Colors.brightBlack,
    Colors.brightRed,
    Colors.brightGreen,
    Colors.brightYellow,
    Colors.brightBlue,
    Colors.brightMagenta,
    Colors.brightCyan,
    Colors.brightWhite,
  ];
  final pal = bright ? brightPal : normal;
  return pal[i.clamp(0, 7)];
}

Color _ansi256ToColor(int i) {
  if (i < 0) return Colors.white;
  if (i < 8) return _ansiFg8(i, bright: false);
  if (i < 16) return _ansiFg8(i - 8, bright: true);
  if (i < 232) {
    final v = i - 16;
    final b = v % 6;
    final g = (v ~/ 6) % 6;
    final r = v ~/ 36;
    int cube(int x) {
      if (x == 0) return 0;
      return 55 + (x - 1) * 40;
    }

    return Color.fromRGB(cube(r), cube(g), cube(b));
  }
  if (i < 256) {
    final g = 8 + (i - 232) * 10;
    return Color.fromRGB(g, g, g);
  }
  return Colors.white;
}
