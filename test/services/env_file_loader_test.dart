import 'dart:io';

import 'package:fastlane_cli/src/services/env_file_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('loadEnvFiles', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('env_loader_');
    });

    tearDown(() async {
      if (temp.existsSync()) {
        await temp.delete(recursive: true);
      }
    });

    File write(String name, String body) {
      final f = File(p.join(temp.path, name));
      f.writeAsStringSync(body);
      return f;
    }

    test('parses basic key=value with comments and blank lines', () {
      final f = write('a.env', '''
# comment
FOO=bar
# another

BAZ=qux
''');
      final merged = loadEnvFiles(<File>[f], <String, String>{});
      expect(merged['FOO'], 'bar');
      expect(merged['BAZ'], 'qux');
      expect(merged.length, 2);
    });

    test('strips matched single/double quotes', () {
      final f = write('a.env', '''
A="double"
B='single'
C=unquoted
D="mixed'
''');
      final merged = loadEnvFiles(<File>[f], <String, String>{});
      expect(merged['A'], 'double');
      expect(merged['B'], 'single');
      expect(merged['C'], 'unquoted');
      // Mismatched quotes are left as-is.
      expect(merged['D'], '"mixed\'');
    });

    test('tolerates `export` prefix', () {
      final f = write('a.env', '''
export FOO=bar
   export BAZ="qux"
''');
      final merged = loadEnvFiles(<File>[f], <String, String>{});
      expect(merged['FOO'], 'bar');
      expect(merged['BAZ'], 'qux');
    });

    test('does NOT interpolate \${OTHER_KEY} (passes through unchanged)', () {
      final f = write('a.env', '''
HOME=/x
GREET=hello \${HOME}
''');
      final merged = loadEnvFiles(<File>[f], <String, String>{});
      expect(merged['HOME'], '/x');
      expect(merged['GREET'], r'hello ${HOME}');
    });

    test(
        'malformed lines emit a structural warning (no value leak) and are skipped',
        () {
      final warnings = StringBuffer();
      final f = write('bad.env', '''
GOOD=ok
NO_EQUALS_HERE
=missing_key
123BAD=foo
ANOTHER_GOOD=fine
''');
      final merged = loadEnvFiles(
        <File>[f],
        <String, String>{},
        warningSink: warnings,
      );
      expect(merged['GOOD'], 'ok');
      expect(merged['ANOTHER_GOOD'], 'fine');
      expect(merged.containsKey('NO_EQUALS_HERE'), isFalse);
      expect(merged.containsKey('123BAD'), isFalse);

      final lines = warnings.toString().split('\n').where((l) => l.isNotEmpty).toList();
      // 3 malformed lines → 3 warnings.
      expect(lines.length, 3);
      // No warning contains a value (structural only).
      for (final line in lines) {
        expect(line.contains('foo'), isFalse,
            reason: 'warnings must not leak values');
        expect(line.contains('fine'), isFalse);
      }
    });

    test('later files override earlier files (ascending precedence)', () {
      final low = write('low.env', 'KEY=low\nA=1\n');
      final high = write('high.env', 'KEY=high\nB=2\n');
      final merged = loadEnvFiles(<File>[low, high], <String, String>{});
      expect(merged['KEY'], 'high');
      expect(merged['A'], '1');
      expect(merged['B'], '2');
    });

    test('shell env overrides every file', () {
      final f = write('a.env', 'KEY=fromfile\nONLY=keep\n');
      final merged = loadEnvFiles(<File>[f], <String, String>{
        'KEY': 'fromshell',
      });
      expect(merged['KEY'], 'fromshell');
      // Shell-only keys are NOT injected into the merge; only keys present
      // in the files are overridden (the child inherits the rest from the
      // parent process by default).
      expect(merged.containsKey('ONLY'), isTrue);
      expect(merged.length, 2);
    });

    test('missing files are silently skipped', () {
      final missing = File(p.join(temp.path, 'nope.env'));
      final good = write('good.env', 'X=y\n');
      final merged = loadEnvFiles(<File>[missing, good], <String, String>{});
      expect(merged, <String, String>{'X': 'y'});
    });
  });
}
