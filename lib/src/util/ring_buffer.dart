/// Fixed-capacity ring buffer with O(1) append.
///
/// Existed previously as an implicit `List.sublist(length - max)` inside
/// `RunSessionController._bounded`, which was O(n) per log line because it
/// copied the entire buffer to drop the oldest entries. For a 100 line/sec
/// build that hammered the render thread (see W9 in the v0.4.4 perf audit).
///
/// This implementation drops oldest entries automatically when [capacity] is
/// exceeded and exposes an [Iterable] view in chronological order. The
/// underlying storage is a single `List<T?>` of fixed length; iteration walks
/// the logical view, never reshuffles storage.
///
/// Not thread-safe. The CLI is single-isolate, so callers (the
/// [RunSessionController]) already serialise mutations through the event
/// loop — we deliberately skip locking.
class RingBuffer<T> extends Iterable<T> {
  RingBuffer(this.capacity)
      : assert(capacity > 0, 'capacity must be positive'),
        _storage = List<T?>.filled(capacity, null, growable: false);

  /// Maximum number of entries retained. Older entries are dropped FIFO when
  /// the buffer is full.
  final int capacity;

  final List<T?> _storage;

  /// Index in `_storage` where the next [add] will write. When [_length]
  /// equals [capacity], this also points at the oldest entry (about to be
  /// overwritten).
  int _head = 0;

  /// Number of live entries (0..capacity).
  int _length = 0;

  /// Monotonic counter incremented on each mutating operation. Lets callers
  /// snapshot the buffer (via `toList()`) and cheaply re-check whether a
  /// further mutation has occurred.
  int _revision = 0;

  int get revision => _revision;

  @override
  int get length => _length;

  @override
  bool get isEmpty => _length == 0;

  @override
  bool get isNotEmpty => _length > 0;

  /// True when the buffer has reached [capacity]. Further [add] calls will
  /// overwrite the oldest entry.
  bool get isFull => _length == capacity;

  /// Append [value]. O(1). When at [capacity], drops the oldest entry.
  void add(T value) {
    _storage[_head] = value;
    _head = (_head + 1) % capacity;
    if (_length < capacity) {
      _length++;
    }
    _revision++;
  }

  /// Append every element in [values] in iteration order. O(values.length).
  void addAll(Iterable<T> values) {
    for (final v in values) {
      add(v);
    }
  }

  /// Drop every entry. Storage is retained (so subsequent appends don't
  /// re-allocate); old refs are cleared so the GC can collect.
  void clear() {
    for (var i = 0; i < capacity; i++) {
      _storage[i] = null;
    }
    _head = 0;
    _length = 0;
    _revision++;
  }

  @override
  T elementAt(int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', null, _length);
    }
    final start = _length < capacity ? 0 : _head;
    return _storage[(start + index) % capacity] as T;
  }

  /// Snapshot the live entries as a fresh growable [List] in chronological
  /// order. Use this when handing the contents to APIs that need an indexable
  /// list and must not see future appends.
  List<T> toListSnapshot() {
    final out = <T>[];
    final start = _length < capacity ? 0 : _head;
    for (var i = 0; i < _length; i++) {
      out.add(_storage[(start + i) % capacity] as T);
    }
    return out;
  }

  @override
  Iterator<T> get iterator => _RingBufferIterator<T>(this);
}

class _RingBufferIterator<T> implements Iterator<T> {
  _RingBufferIterator(this._buffer)
      : _start = _buffer._length < _buffer.capacity ? 0 : _buffer._head,
        _snapshotLength = _buffer._length;

  final RingBuffer<T> _buffer;
  final int _start;
  final int _snapshotLength;
  int _i = -1;

  @override
  T get current {
    if (_i < 0 || _i >= _snapshotLength) {
      throw StateError('Iterator out of range — call moveNext first.');
    }
    return _buffer._storage[(_start + _i) % _buffer.capacity] as T;
  }

  @override
  bool moveNext() {
    _i++;
    return _i < _snapshotLength;
  }
}
