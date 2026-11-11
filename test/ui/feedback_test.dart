// Banner, status strip, empty state, progress and skeleton.

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/ui/feedback/atomic_banner.dart';
import 'package:atomic_notes/ui/feedback/empty_state.dart';
import 'package:atomic_notes/ui/feedback/progress.dart';
import 'package:atomic_notes/ui/feedback/status_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/themed.dart';

void main() {
  for (final MapEntry(key: name, value: theme) in atomicThemes.entries) {
    final c = theme.extension<AtomicColors>()!;

    group('AtomicBanner ($name)', () {
      testWidgets('the card stays surface; only the circle takes the tone',
          (tester) async {
        for (final (tone, fill) in [
          (BannerTone.info, c.info),
          (BannerTone.attention, c.accent),
          (BannerTone.danger, c.danger),
        ]) {
          await pumpThemed(
              tester,
              AtomicBanner(
                  tone: tone,
                  icon: AtomicIcons.infoCircle,
                  title: 'Requirements',
                  body: 'Cloud sync must be on.'),
              theme: theme);
          final boxes = tester
              .widgetList<DecoratedBox>(find.descendant(
                  of: find.byType(AtomicBanner),
                  matching: find.byType(DecoratedBox)))
              .map((b) => (b.decoration as BoxDecoration).color)
              .toList();
          expect(boxes.first, c.surface, reason: tone.name);
          expect(boxes, contains(fill), reason: tone.name);
        }
      });

      testWidgets('fits 2.0 text in 320 dp', (tester) async {
        await pumpNarrow(
          tester,
          const AtomicBanner(
            tone: BannerTone.danger,
            icon: AtomicIcons.alertTriangle,
            title: 'Your recovery phrase is not saved',
            body: 'Without it, a lost device means lost encrypted notes.',
          ),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('StatusStrip ($name)', () {
      for (final (level, colour) in [
        (QuotaLevel.normal, c.textSecondary),
        (QuotaLevel.low, c.accentText),
        (QuotaLevel.limit, c.dangerText),
      ]) {
        testWidgets('quota colour at ${level.name}', (tester) async {
          await pumpThemed(
            tester,
            StatusStrip(
              leading: const SizedBox.square(dimension: 56),
              greeting: 'Good evening',
              quota: '28 of 30 notes',
              quotaLevel: level,
              detail: '2 waiting to sync',
            ),
            theme: theme,
          );
          final rich = tester.widget<RichText>(find.byWidgetPredicate((w) =>
              w is RichText &&
              w.text.toPlainText() == '28 of 30 notes · 2 waiting to sync'));
          TextSpan? quota;
          rich.text.visitChildren((span) {
            if (span is TextSpan && span.text == '28 of 30 notes') {
              quota = span;
              return false;
            }
            return true;
          });
          expect(quota?.style?.color, colour);
        });
      }

      testWidgets('fits 2.0 text in 320 dp', (tester) async {
        await pumpNarrow(
          tester,
          const StatusStrip(
            leading: SizedBox.square(dimension: 56),
            greeting: 'Good afternoon',
            quota: 'Note limit reached',
            quotaLevel: QuotaLevel.limit,
            detail: '12 waiting to sync',
          ),
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('EmptyState: headline, line and optional action ($name)',
        (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpNarrow(
        tester,
        EmptyState(
          art: const SizedBox.square(dimension: 96),
          title: 'Write your first note',
          body: 'Tap + to start. You can switch to a checklist in the editor.',
          actionLabel: 'New note',
          onAction: () => taps++,
        ),
        theme: theme,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSemantics(find.text('Write your first note')),
          isSemantics(isHeader: true));
      await tester.tap(find.text('New note'));
      expect(taps, 1);
      handle.dispose();
    });

    group('progress ($name)', () {
      testWidgets('ProgressBar grows from zero and reports its value',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpThemed(
            tester,
            const SizedBox(
                width: 200,
                child: ProgressBar(
                    value: 0.5,
                    semanticsLabel: 'Notes used',
                    semanticsValue: '15 of 30')),
            theme: theme);
        double width() => tester
            .getSize(find.descendant(
                of: find.byType(FractionallySizedBox),
                matching: find.byType(DecoratedBox)))
            .width;
        expect(width(), 0);
        await tester.pumpAndSettle();
        expect(width(), closeTo(100, 0.5));
        expect(tester.getSemantics(find.byType(ProgressBar)),
            isSemantics(label: 'Notes used', value: '15 of 30'));
        handle.dispose();
      });

      testWidgets('reduced motion fills at once', (tester) async {
        await pumpThemed(
            tester, const SizedBox(width: 200, child: ProgressBar(value: 1)),
            theme: theme, disableAnimations: true);
        await tester.pump();
        expect(
            tester
                .getSize(find.descendant(
                    of: find.byType(FractionallySizedBox),
                    matching: find.byType(DecoratedBox)))
                .width,
            200);
      });

      testWidgets('ProgressRing uses the accent on the inset colour',
          (tester) async {
        await pumpThemed(tester, const ProgressRing(value: 0.3), theme: theme);
        final ring = tester.widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator));
        expect(ring.color, c.accent);
        expect(ring.backgroundColor, c.surfaceInset);
        expect(ring.strokeWidth, 2.5);
      });

      testWidgets('Skeleton pulses, and stops under reduced motion',
          (tester) async {
        await pumpThemed(tester, const Skeleton(width: 120), theme: theme);
        double opacity() => tester
            .widget<FadeTransition>(find.descendant(
                of: find.byType(Skeleton),
                matching: find.byType(FadeTransition)))
            .opacity
            .value;
        final a = opacity();
        await tester.pump(const Duration(milliseconds: 600));
        expect(opacity(), isNot(a));

        await pumpThemed(tester, const Skeleton(width: 120),
            theme: theme, disableAnimations: true);
        final b = opacity();
        await tester.pump(const Duration(milliseconds: 600));
        expect(opacity(), b);
      });
    });
  }
}
