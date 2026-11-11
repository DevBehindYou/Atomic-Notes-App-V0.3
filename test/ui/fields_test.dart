// Text, search, code and phrase fields (components spec).

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/ui/fields/atomic_text_field.dart';
import 'package:atomic_notes/ui/fields/code_field.dart';
import 'package:atomic_notes/ui/fields/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

InputDecoration _decoration(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).decoration!;

void main() {
  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    final c = theme.extension<AtomicColors>()!;

    group('AtomicTextField ($name)', () {
      testWidgets('label names the field; borders follow focus and error',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(
          tester,
          const AtomicTextField(
              label: 'Display name', hintText: 'For example, Sam'),
          theme: theme,
        );
        expect(
            tester.getSemantics(find.byType(TextField)),
            isSemantics(
                // The label names the field; the example hint follows.
                label: 'Display name\nFor example, Sam',
                isTextField: true,
                hasTapAction: true));
        final d = _decoration(tester);
        expect(d.fillColor, c.surfaceInset);
        expect((d.enabledBorder! as OutlineInputBorder).borderSide.color,
            c.outlineStrong);
        expect((d.focusedBorder! as OutlineInputBorder).borderSide.width, 2);
        expect(
            (d.focusedBorder! as OutlineInputBorder).borderSide.color, c.focus);
        handle.dispose();
      });

      testWidgets('an error shows the danger border and the message',
          (tester) async {
        await pumpThemed(
          tester,
          const AtomicTextField(
              label: 'Name', errorText: 'Use 3 to 20 characters'),
          theme: theme,
        );
        expect(find.text('Use 3 to 20 characters'), findsOneWidget);
        final d = _decoration(tester);
        expect(
            (d.errorBorder! as OutlineInputBorder).borderSide.color, c.danger);
      });

      testWidgets('fits 2.0 text in 320 dp, with an error', (tester) async {
        await pumpNarrow(
          tester,
          const AtomicTextField(
            label: 'Recovery email address',
            hintText: 'For example, sam@example.com',
            errorText: 'That address is missing an @ sign. Check and retry.',
          ),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('SearchField ($name)', () {
      testWidgets('clear appears with text, clears and reports the change',
          (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final changes = <String>[];
        var cancels = 0;
        await pumpThemed(
          tester,
          SearchField(
            controller: controller,
            onChanged: changes.add,
            onCancel: () => cancels++,
          ),
          theme: theme,
        );
        expect(find.text('Search notes or #tags'), findsOneWidget);
        expect(find.byTooltip('Clear search'), findsNothing);
        await tester.enterText(find.byType(TextField), '#work');
        await tester.pump();
        expect(find.byTooltip('Clear search'), findsOneWidget);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pump();
        expect(controller.text, isEmpty);
        expect(changes, ['#work', '']);
        await tester.tap(find.text('Cancel'));
        expect(cancels, 1);
        expect(_decoration(tester).fillColor, c.surfaceRaised);
      });

      testWidgets('fits 2.0 text in 320 dp', (tester) async {
        final controller = TextEditingController(text: 'groceries');
        addTearDown(controller.dispose);
        await pumpNarrow(
            tester, SearchField(controller: controller, onCancel: () {}),
            theme: theme);
        expect(tester.takeException(), isNull);
      });
    });

    group('CodeField ($name)', () {
      testWidgets('six digits only; completes at six', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final completed = <String>[];
        await pumpThemed(tester,
            CodeField(controller: controller, onCompleted: completed.add),
            theme: theme);
        expect(find.text('6-digit code'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '12a34');
        expect(controller.text, '1234');
        expect(completed, isEmpty);
        await tester.enterText(find.byType(TextField), '12345678');
        expect(controller.text, '123456');
        expect(completed, ['123456']);
        expect(tester.widget<TextField>(find.byType(TextField)).textAlign,
            TextAlign.center);
      });

      testWidgets('recovery codes: upper-cased, hyphen kept, eleven long',
          (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpThemed(
            tester, CodeField(controller: controller, recovery: true),
            theme: theme);
        expect(find.text('Recovery code'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'ab1cd-ef2gh!xyz');
        expect(controller.text, 'AB1CD-EF2GH');
      });

      testWidgets('fits 2.0 text in 320 dp with an error', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpNarrow(
          tester,
          CodeField(
              controller: controller,
              recovery: true,
              errorText: 'That code did not work. Try another one.'),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('PhraseField: no autocorrect, no suggestions ($name)',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpNarrow(tester, PhraseField(controller: controller),
          theme: theme);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.textCapitalization, TextCapitalization.none);
      expect(find.text('Recovery phrase'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
