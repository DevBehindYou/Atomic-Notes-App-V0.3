// Page header, page title and selection bar (screens and components specs).

import 'package:atomic_notes/ui/headers/page_header.dart';
import 'package:atomic_notes/ui/headers/selection_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

void main() {
  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    group('AtomicPageHeader ($name)', () {
      testWidgets('the back button is named and pops the page', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Column(children: [
                      AtomicPageHeader(title: 'Recycle Bin'),
                      PageTitle('Recycle Bin'),
                    ]),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Back'), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget);
      });

      testWidgets('the small title shows only once scrolled', (tester) async {
        double opacity() => tester
            .widget<AnimatedOpacity>(find.ancestor(
                of: find.text('Energy'),
                matching: find.byType(AnimatedOpacity)))
            .opacity;
        await pumpThemed(tester, const AtomicPageHeader(title: 'Energy'),
            theme: theme);
        expect(opacity(), 0);
        await pumpThemed(
            tester, const AtomicPageHeader(title: 'Energy', showTitle: true),
            theme: theme);
        expect(opacity(), 1);
      });

      testWidgets('header and title fit 2.0 text in 320 dp', (tester) async {
        await pumpNarrow(
          tester,
          Column(children: [
            AtomicPageHeader(
              title: 'Two-factor authentication settings',
              showTitle: true,
              onBack: () {},
              actions: const [SizedBox.square(dimension: 48)],
            ),
            const PageTitle('Two-factor authentication'),
          ]),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('SelectionBar ($name)', () {
      testWidgets('every control calls back', (tester) async {
        final calls = <String>[];
        await pumpThemed(
          tester,
          SelectionBar(
            count: 3,
            onCancel: () => calls.add('cancel'),
            onSelectAll: () => calls.add('all'),
            onDelete: () => calls.add('delete'),
          ),
          theme: theme,
        );
        expect(find.text('3 selected'), findsOneWidget);
        await tester.tap(find.byTooltip('Cancel selection'));
        await tester.tap(find.text('Select all'));
        await tester.tap(find.text('Delete'));
        expect(calls, ['cancel', 'all', 'delete']);
      });

      testWidgets('wraps without overflow at 2.0 text in 320 dp',
          (tester) async {
        await pumpNarrow(
          tester,
          SelectionBar(
              count: 128, onCancel: () {}, onSelectAll: () {}, onDelete: () {}),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}
