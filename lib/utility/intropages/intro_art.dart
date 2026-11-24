import 'dart:math' as math;

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/motion/ambient.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

/// Onboarding illustrations, drawn rather than shipped as PNGs.
///
/// Built from the design system's own vocabulary (cards, lines, accent
/// marks) and painted from the current theme's colour roles, so they scale
/// to any screen and follow light and dark automatically.
enum IntroArtKind { grid, editor, sync, lock }

class IntroArt extends StatelessWidget {
  final IntroArtKind kind;
  const IntroArt(this.kind, {super.key});

  /// What each illustration shows, for screen readers.
  static String labelOf(IntroArtKind kind) => switch (kind) {
        IntroArtKind.grid => 'Illustration: a grid of note cards',
        IntroArtKind.editor => 'Illustration: a note with a checklist',
        IntroArtKind.sync => 'Illustration: a note syncing between two devices',
        IntroArtKind.lock => 'Illustration: a padlock over a stack of notes',
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: labelOf(kind),
      child: AspectRatio(
        aspectRatio: 1.15,
        child: CustomPaint(
          painter: _IntroPainter(kind, context.colors),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  final IntroArtKind kind;
  final AtomicColors c;
  _IntroPainter(this.kind, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    _grid(canvas, size);
    switch (kind) {
      case IntroArtKind.grid:
        _paintGrid(canvas, size);
      case IntroArtKind.editor:
        _paintEditor(canvas, size);
      case IntroArtKind.sync:
        _paintSync(canvas, size);
      case IntroArtKind.lock:
        _paintLock(canvas, size);
    }
  }

  /// Faint engineering grid behind everything.
  void _grid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = c.outline.withValues(alpha: 0.5)
      ..strokeWidth = 0.6;
    const step = 22.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  Paint get _ink => Paint()
    ..color = c.textPrimary
    ..style = PaintingStyle.fill;

  Paint get _stroke => Paint()
    ..color = c.textPrimary
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  Paint get _accent => Paint()
    ..color = c.accent
    ..style = PaintingStyle.fill;

  void _card(Canvas canvas, Rect r, {bool accent = false}) {
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
    canvas.drawRRect(
        rr,
        Paint()
          ..color = c.surface
          ..style = PaintingStyle.fill);
    canvas.drawRRect(rr, accent ? (_stroke..color = c.accentText) : _stroke);
  }

  void _line(Canvas canvas, double x, double y, double w,
      {double h = 4, Color? color}) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h), const Radius.circular(2)),
      Paint()..color = color ?? c.outlineStrong,
    );
  }

  /// 1 — a masonry wall of note cards.
  void _paintGrid(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final colW = w * 0.36;
    final heights = [
      [h * 0.30, h * 0.22, h * 0.26],
      [h * 0.22, h * 0.32, h * 0.24],
    ];
    for (int col = 0; col < 2; col++) {
      double y = h * 0.10;
      final x = w * (col == 0 ? 0.12 : 0.52);
      for (int i = 0; i < heights[col].length; i++) {
        final ch = heights[col][i];
        if (y + ch > h * 0.92) break;
        final accent = col == 1 && i == 1;
        _card(canvas, Rect.fromLTWH(x, y, colW, ch), accent: accent);
        _line(canvas, x + 8, y + 9, colW * 0.5, h: 3);
        _line(canvas, x + 8, y + 20, colW * 0.72, h: 5, color: c.textPrimary);
        _line(canvas, x + 8, y + 32, colW * 0.62);
        if (ch > h * 0.25) _line(canvas, x + 8, y + 41, colW * 0.4);
        y += ch + h * 0.035;
      }
    }
  }

  /// 2 — the editor: title rule, body lines, a checklist forming.
  void _paintEditor(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = Rect.fromLTWH(w * 0.12, h * 0.12, w * 0.76, h * 0.76);
    _card(canvas, r);

    final x = r.left + 14;
    _line(canvas, x, r.top + 14, r.width * 0.34, h: 3);
    canvas.drawLine(
        Offset(x, r.top + 28),
        Offset(r.right - 14, r.top + 28),
        Paint()
          ..color = c.textPrimary
          ..strokeWidth = 1);
    _line(canvas, x, r.top + 38, r.width * 0.6, h: 8, color: c.textPrimary);

    // Checklist rows — two ticked, one open.
    double y = r.top + 62;
    for (int i = 0; i < 3; i++) {
      final box = Rect.fromLTWH(x, y, 10, 10);
      if (i < 2) {
        canvas.drawRect(box, _accent);
        final tick = Path()
          ..moveTo(box.left + 2.5, box.top + 5)
          ..lineTo(box.left + 4.5, box.top + 7.2)
          ..lineTo(box.left + 7.8, box.top + 2.8);
        canvas.drawPath(
            tick,
            Paint()
              ..color = c.onAccent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6);
      } else {
        canvas.drawRect(
            box,
            Paint()
              ..color = c.textPrimary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2);
      }
      _line(canvas, x + 18, y + 3, r.width * (i == 2 ? 0.38 : 0.54),
          color: i < 2 ? c.outlineStrong : c.textPrimary);
      y += 20;
    }

    // Caret.
    canvas.drawRect(
        Rect.fromLTWH(x + 18 + r.width * 0.38 + 3, y - 20, 1.5, 11), _accent);
  }

  /// 3 — two devices, one arc: the same note on both.
  void _paintSync(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final left = Rect.fromLTWH(w * 0.08, h * 0.30, w * 0.26, h * 0.42);
    final right = Rect.fromLTWH(w * 0.66, h * 0.30, w * 0.26, h * 0.42);
    _card(canvas, left, accent: true);
    _card(canvas, right, accent: true);

    for (final r in [left, right]) {
      _line(canvas, r.left + 6, r.top + 10, r.width * 0.6, h: 3);
      _line(canvas, r.left + 6, r.top + 20, r.width * 0.75,
          h: 5, color: c.textPrimary);
      _line(canvas, r.left + 6, r.top + 31, r.width * 0.5);
    }

    // The arc between them, with an arrowhead — data in flight.
    final arc = Path()
      ..moveTo(left.right, h * 0.44)
      ..cubicTo(w * 0.44, h * 0.14, w * 0.56, h * 0.14, right.left, h * 0.44);
    canvas.drawPath(
        arc,
        Paint()
          ..color = c.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    final head = Path()
      ..moveTo(right.left, h * 0.44)
      ..lineTo(right.left - 9, h * 0.40)
      ..lineTo(right.left - 8, h * 0.475)
      ..close();
    canvas.drawPath(head, _accent);

    // Return arc, quieter.
    final back = Path()
      ..moveTo(right.left, h * 0.62)
      ..cubicTo(w * 0.56, h * 0.86, w * 0.44, h * 0.86, left.right, h * 0.62);
    canvas.drawPath(
        back,
        Paint()
          ..color = c.outlineStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    final head2 = Path()
      ..moveTo(left.right, h * 0.62)
      ..lineTo(left.right + 9, h * 0.585)
      ..lineTo(left.right + 8, h * 0.66)
      ..close();
    canvas.drawPath(head2, Paint()..color = c.outlineStrong);
  }

  /// 4 — a padlock built from the same square language, over a note stack.
  void _paintLock(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Stack behind.
    for (int i = 2; i >= 0; i--) {
      final inset = i * 10.0;
      _card(
          canvas,
          Rect.fromLTWH(w * 0.20 + inset, h * 0.20 + inset,
              w * 0.60 - inset * 2, h * 0.60 - inset * 2));
    }

    // Shackle.
    final cx = w / 2;
    final shackle = Rect.fromCenter(
        center: Offset(cx, h * 0.46), width: w * 0.20, height: h * 0.22);
    canvas.drawArc(
        shackle,
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = c.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.butt);

    // Body.
    final body = Rect.fromCenter(
        center: Offset(cx, h * 0.62), width: w * 0.30, height: h * 0.20);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(6)), _ink);

    // Keyhole in the accent.
    canvas.drawCircle(Offset(cx, body.center.dy - 3), 4.5, _accent);
    canvas.drawRect(
        Rect.fromLTWH(cx - 1.6, body.center.dy - 1, 3.2, 10), _accent);
  }

  @override
  bool shouldRepaint(covariant _IntroPainter old) =>
      old.kind != kind || old.c != c;
}

/// One page of an intro tour.
class IntroTourPage {
  const IntroTourPage({
    required this.art,
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  /// Built per frame so it can follow reduced motion. It should carry its
  /// own semantics label.
  final WidgetBuilder art;
  final String eyebrow;
  final String title;
  final String body;
}

/// The shared chrome of the onboarding tour and the Energy intro (screens
/// spec, Onboarding and Energy intro): "Skip" top right, then per page the
/// art in a large-radius frame filling about 45% of the height, the
/// headline in `display` and the body in `bodyLarge` `textSecondary`; at
/// the bottom the page-indicator pill on the left and a 64 dp accent round
/// "Next" button on the right, which becomes a [doneLabel] pill on the last
/// page.
///
/// Both Skip and the last-page action call [onFinish], once. Page changes slide
/// unless reduced motion is on, when they jump. The art floats gently on the
/// ambient budget and holds still under reduced motion.
class IntroTour extends StatefulWidget {
  const IntroTour({
    super.key,
    required this.pages,
    required this.doneLabel,
    required this.onFinish,
  });

  final List<IntroTourPage> pages;
  final String doneLabel;
  final VoidCallback onFinish;

  @override
  State<IntroTour> createState() => _IntroTourState();
}

class _IntroTourState extends State<IntroTour> {
  final PageController _controller = PageController();
  int _page = 0;

  bool _finished = false;

  bool get _onLastPage => _page == widget.pages.length - 1;

  /// Skip and the last-page action leave once, however fast they are tapped.
  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinish();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    final target = (_page + 1).clamp(0, widget.pages.length - 1);
    if (AtomicMotion.reduced(context)) {
      _controller.jumpToPage(target);
    } else {
      _controller.animateToPage(target,
          duration: AtomicMotion.emphasized,
          curve: AtomicMotion.emphasizedCurve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = widget.pages.length;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AtomicSpace.x5, AtomicSpace.x2, AtomicSpace.x3, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: AtomicButton.text(
                  key: const ValueKey('intro-skip'),
                  label: 'Skip',
                  onPressed: _finish,
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: total,
                onPageChanged: (v) => setState(() => _page = v),
                itemBuilder: (context, i) => _IntroTourPageView(
                  page: widget.pages[i],
                  index: i,
                  total: total,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AtomicSpace.x5, AtomicSpace.x3,
                  AtomicSpace.x5, AtomicSpace.x6),
              child: Row(
                children: [
                  Semantics(
                    key: const ValueKey('intro-indicator'),
                    label: 'Page ${_page + 1} of $total',
                    child: ExcludeSemantics(
                      child: SmoothPageIndicator(
                        controller: _controller,
                        count: total,
                        effect: ExpandingDotsEffect(
                          dotHeight: 8,
                          dotWidth: 8,
                          expansionFactor: 3,
                          spacing: 6,
                          dotColor: c.outlineStrong,
                          activeDotColor: c.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AtomicSpace.x4),
                  const Spacer(),
                  if (_onLastPage)
                    Flexible(
                      flex: 4,
                      child: AtomicButton.primary(
                        key: const ValueKey('intro-done'),
                        label: widget.doneLabel,
                        size: AtomicButtonSize.large,
                        onPressed: _finish,
                      ),
                    )
                  else
                    _NextButton(onPressed: _next),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 64 dp accent round "Next" button with an arrow.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.onPressed});
  final VoidCallback onPressed;

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: 'Next',
      excludeFromSemantics: true,
      child: AtomicPressable(
        key: const ValueKey('intro-next'),
        onTap: onPressed,
        semanticsLabel: 'Next',
        excludeSemantics: true,
        minSize: size,
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            child: Icon(AtomicIcons.arrowRight, size: 28, color: c.onAccent),
          ),
        ),
      ),
    );
  }
}

class _IntroTourPageView extends StatelessWidget {
  const _IntroTourPageView(
      {required this.page, required this.index, required this.total});
  final IntroTourPage page;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final artHeight = math.max(120.0, constraints.maxHeight * 0.45);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: AtomicSpace.x5, vertical: AtomicSpace.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: artHeight,
                child: DecoratedBox(
                  key: ValueKey('intro-art-frame-$index'),
                  decoration: BoxDecoration(
                    color: c.surfaceInset,
                    borderRadius: AtomicRadius.xLargeAll,
                  ),
                  child: ClipRRect(
                    borderRadius: AtomicRadius.xLargeAll,
                    child: Padding(
                      padding: const EdgeInsets.all(AtomicSpace.x4),
                      child: Ambient(
                        period: const Duration(seconds: 6),
                        child: Center(child: page.art(context)),
                        builder: (context, t, child) => Transform.translate(
                          offset: Offset(0, -6 * t),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AtomicSpace.x6),
              Text(
                page.eyebrow,
                key: ValueKey('intro-eyebrow-$index'),
                style: AtomicType.labelLarge.copyWith(color: c.accentText),
              ),
              const SizedBox(height: AtomicSpace.x2),
              Semantics(
                header: true,
                child: Text(
                  page.title,
                  key: ValueKey('intro-title-$index'),
                  style: AtomicType.display.copyWith(color: c.textPrimary),
                ),
              ),
              const SizedBox(height: AtomicSpace.x3),
              Text(
                page.body,
                key: ValueKey('intro-body-$index'),
                style: AtomicType.bodyLarge.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AtomicSpace.x4),
            ],
          ),
        );
      },
    );
  }
}
