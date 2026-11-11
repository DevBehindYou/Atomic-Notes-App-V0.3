// Filter, tag, editor tag and status chips (components spec, Chips).

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/ui/chips/atomic_filter_chip.dart';
import 'package:atomic_notes/ui/chips/count_bubble.dart';
import 'package:atomic_notes/ui/chips/status_chip.dart';
import 'package:atomic_notes/ui/chips/tag_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

const _longTag = 'a-very-long-legacy-tag-of-forty-units-xx';

void main() {
  test('counts above 99 read 99+', () {
    expect(CountBubble.format(7), '7');
    expect(CountBubble.format(99), '99');
    expect(CountBubble.format(100), '99+');
  });

  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    final c = theme.extension<AtomicColors>()!;

    group('AtomicFilterChip ($name)', () {
      testWidgets('selected and unselected fills and semantics',
          (tester) async {
        final handle = tester.ensureSemantics();
        var picked = 0;
        await pumpThemed(
          tester,
          Row(children: [
            AtomicFilterChip(
                label: 'All', count: 12, selected: true, onSelected: () {}),
            AtomicFilterChip(
                label: 'Notes',
                count: 9,
                selected: false,
                onSelected: () => picked++),
          ]),
          theme: theme,
        );
        BoxDecoration deco(String label) => tester
            .widget<AnimatedContainer>(find.ancestor(
                of: find.text(label), matching: find.byType(AnimatedContainer)))
            .decoration! as BoxDecoration;
        expect(deco('All').color, c.inverseSurface);
        expect(deco('Notes').color, c.surface);
        expect(
            tester.getSemantics(find.bySemanticsLabel('All, 12')),
            isSemantics(
                isButton: true, hasSelectedState: true, isSelected: true));
        expect(tester.getSemantics(find.bySemanticsLabel('Notes, 9')),
            isSemantics(hasSelectedState: true, isSelected: false));
        await tester.tap(find.text('Notes'));
        expect(picked, 1);
        expect(tester.getSize(find.byType(AtomicFilterChip).last).height,
            greaterThanOrEqualTo(48));
        handle.dispose();
      });

      testWidgets('a long tag truncates on screen but not for screen readers',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(
            tester,
            Center(
                child: AtomicFilterChip.tag(
                    tag: _longTag,
                    count: 3,
                    selected: false,
                    onSelected: () {})),
            theme: theme);
        expect(tester.getSize(find.text('#$_longTag')).width,
            lessThanOrEqualTo(160));
        expect(find.bySemanticsLabel('#$_longTag, 3'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('a chip row fits 2.0 text in 320 dp', (tester) async {
        await pumpNarrow(
          tester,
          Wrap(children: [
            AtomicFilterChip(
                label: 'To-dos', count: 140, selected: true, onSelected: () {}),
            AtomicFilterChip.tag(
                tag: _longTag, count: 1, selected: false, onSelected: () {}),
          ]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('TagChip ($name)', () {
      testWidgets('keeps the "Remove tag {tag}" tooltip and calls back',
          (tester) async {
        var removed = 0;
        await pumpThemed(tester,
            Center(child: TagChip(tag: 'work', onRemove: () => removed++)),
            theme: theme);
        expect(find.text('#work'), findsOneWidget);
        await tester.tap(find.byTooltip('Remove tag work'));
        expect(removed, 1);
        final remove = find.ancestor(
            of: find.byTooltip('Remove tag work'),
            matching: find.byType(TagChip));
        expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
      });

      testWidgets('Add tag is a labelled button', (tester) async {
        final handle = tester.ensureSemantics();
        var adds = 0;
        await pumpThemed(
            tester, Center(child: AddTagChip(onPressed: () => adds++)),
            theme: theme);
        await tester.tap(find.bySemanticsLabel('Add tag'));
        expect(adds, 1);
        handle.dispose();
      });

      testWidgets('editor chips fit 2.0 text in 320 dp', (tester) async {
        await pumpNarrow(
          tester,
          Wrap(children: [
            TagChip(tag: _longTag, onRemove: () {}),
            AddTagChip(onPressed: () {}),
          ]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('StatusChip tones use their roles ($name)', (tester) async {
      await pumpThemed(
        tester,
        const Column(children: [
          StatusChip('Current', tone: StatusTone.inverse),
          StatusChip('Off', tone: StatusTone.danger),
        ]),
        theme: theme,
      );
      expect(
          tester.widget<Text>(find.text('Current')).style?.color, c.onInverse);
      expect(tester.widget<Text>(find.text('Off')).style?.color, c.onDanger);
      await pumpNarrow(
          tester,
          const StatusChip('Two-factor sign-in is waiting for a code',
              tone: StatusTone.accent),
          theme: theme);
      expect(tester.takeException(), isNull);
    });
  }
}
