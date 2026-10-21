import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:atomic_notes/mascot/mascot_sequence.dart';

void main() {
  test('shuffle bags cover all slots with no adjacent repeat', () {
    final s = MascotSequence(Random(12), [1, 2, 3, 4]);
    final values = List.generate(400, (_) => s.next());
    for (var i = 0; i < values.length; i += 4) {
      expect(values.sublist(i, i + 4).toSet().length, 4);
    }
    for (var i = 1; i < values.length; i++) {
      expect(values[i], isNot(values[i - 1]));
    }
  });
  test('failure exclusion exhausts and retry resets', () {
    final s = MascotSequence(Random(3), [1, 2, 3, 4]);
    for (final slot in [1, 2, 3, 4]) {
      s.excludeFailed(slot);
    }
    expect(s.next(), isNull);
    s.reset();
    expect(s.next(), isNotNull);
  });
}
