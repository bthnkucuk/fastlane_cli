import 'package:fastlane_cli/src/util/ring_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('RingBuffer', () {
    test('rejects non-positive capacity', () {
      expect(() => RingBuffer<int>(0), throwsA(isA<AssertionError>()));
    });

    test('starts empty', () {
      final r = RingBuffer<int>(4);
      expect(r.length, 0);
      expect(r.isEmpty, isTrue);
      expect(r.isNotEmpty, isFalse);
      expect(r.isFull, isFalse);
      expect(r.toListSnapshot(), <int>[]);
    });

    test('add stores entries in chronological order', () {
      final r = RingBuffer<int>(4);
      r.add(1);
      r.add(2);
      r.add(3);
      expect(r.length, 3);
      expect(r.isFull, isFalse);
      expect(r.toListSnapshot(), <int>[1, 2, 3]);
    });

    test('overflows by dropping oldest entries FIFO', () {
      final r = RingBuffer<int>(3);
      r.add(1);
      r.add(2);
      r.add(3);
      expect(r.toListSnapshot(), <int>[1, 2, 3]);
      r.add(4);
      expect(r.length, 3);
      expect(r.isFull, isTrue);
      expect(r.toListSnapshot(), <int>[2, 3, 4]);
      r.add(5);
      r.add(6);
      expect(r.toListSnapshot(), <int>[4, 5, 6]);
    });

    test('addAll preserves iteration order', () {
      final r = RingBuffer<int>(5);
      r.addAll(<int>[10, 20, 30]);
      expect(r.toListSnapshot(), <int>[10, 20, 30]);
      r.addAll(<int>[40, 50, 60, 70]);
      // capacity 5, last 5 wins
      expect(r.toListSnapshot(), <int>[30, 40, 50, 60, 70]);
    });

    test('elementAt walks in chronological order', () {
      final r = RingBuffer<int>(3);
      r.add(1);
      r.add(2);
      r.add(3);
      r.add(4); // drops 1
      expect(r.elementAt(0), 2);
      expect(r.elementAt(1), 3);
      expect(r.elementAt(2), 4);
      expect(() => r.elementAt(3), throwsA(isA<RangeError>()));
      expect(() => r.elementAt(-1), throwsA(isA<RangeError>()));
    });

    test('clear empties the buffer and lets storage be reused', () {
      final r = RingBuffer<String>(2);
      r.add('a');
      r.add('b');
      r.add('c'); // drops 'a'
      r.clear();
      expect(r.length, 0);
      expect(r.toListSnapshot(), <String>[]);
      r.add('x');
      expect(r.toListSnapshot(), <String>['x']);
    });

    test('iterator walks chronologically including after wrap-around', () {
      final r = RingBuffer<int>(3);
      for (var i = 0; i < 7; i++) {
        r.add(i);
      }
      // Wrapped: 4, 5, 6 are alive.
      expect(r.toList(), <int>[4, 5, 6]);
    });

    test('toListSnapshot returns a fresh list (mutation safety)', () {
      final r = RingBuffer<int>(4);
      r.addAll(<int>[1, 2, 3]);
      final snap = r.toListSnapshot();
      r.add(4);
      // snap must NOT pick up the post-snapshot append.
      expect(snap, <int>[1, 2, 3]);
      expect(r.toListSnapshot(), <int>[1, 2, 3, 4]);
    });

    test('revision counter monotonically increases on mutations', () {
      final r = RingBuffer<int>(2);
      final r0 = r.revision;
      r.add(1);
      expect(r.revision, greaterThan(r0));
      final r1 = r.revision;
      r.add(2);
      expect(r.revision, greaterThan(r1));
      final r2 = r.revision;
      r.clear();
      expect(r.revision, greaterThan(r2));
    });
  });
}
