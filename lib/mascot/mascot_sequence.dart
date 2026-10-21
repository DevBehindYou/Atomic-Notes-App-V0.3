import 'dart:math';

/// Timing-free shuffle bag. A null result means every variation failed.
class MascotSequence {
  MascotSequence(this.random, Iterable<int> slots, {int? previousSlot})
      : _slots = List.unmodifiable(slots),
        _previous = previousSlot;
  final Random random;
  final List<int> _slots;
  final Set<int> _failed = {};
  final List<int> _bag = [];
  int? _previous;
  int? next() {
    if (_bag.isEmpty) {
      _bag.addAll(_slots.where((s) => !_failed.contains(s)));
      if (_bag.isEmpty) return null;
      _bag.shuffle(random);
      if (_bag.length > 1 && _bag.first == _previous) {
        final other = 1 + random.nextInt(_bag.length - 1);
        final first = _bag[0];
        _bag[0] = _bag[other];
        _bag[other] = first;
      }
    }
    return _previous = _bag.removeAt(0);
  }

  void excludeFailed(int slot) {
    _failed.add(slot);
    _bag.remove(slot);
  }

  void reset() {
    _failed.clear();
    _bag.clear();
    _previous = null;
  }
}
