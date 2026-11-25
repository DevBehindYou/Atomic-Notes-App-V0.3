import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';

/// Shown when Supabase or Hive can't be initialised at all. There is no usable
/// app behind this point, so it just explains itself instead of disappearing.
///
/// Layout (screens spec, Splash and startup failure): the empty-state layout
/// with a danger icon circle, "Atomic couldn't start", the existing text, and
/// the trace in a `mono` `surfaceInset` box. The trace stays behind "Show
/// details" so the first thing read is the plain explanation, not a raw
/// error.
///
/// It follows the system light or dark setting only. The saved appearance
/// choice and the rest of startup may never have loaded, so nothing here
/// reads them.
class StartupFailedApp extends StatelessWidget {
  final String error;
  const StartupFailedApp({required this.error, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AtomicTheme.light,
      darkTheme: AtomicTheme.dark,
      themeMode: ThemeMode.system,
      home: StartupFailedPage(error: error),
    );
  }
}

/// The screen inside [StartupFailedApp].
class StartupFailedPage extends StatefulWidget {
  const StartupFailedPage({required this.error, super.key});

  final String error;

  static const String title = "Atomic couldn't start";
  static const String body =
      'Check your connection and reopen the app. If this keeps happening, '
      'the details below will say why.';
  static const String showDetails = 'Show details';
  static const String hideDetails = 'Hide details';

  @override
  State<StartupFailedPage> createState() => _StartupFailedPageState();
}

class _StartupFailedPageState extends State<StartupFailedPage> {
  bool _details = false;

  /// The theme's tokens, or the system brightness's own tokens when the
  /// theme carries none.
  AtomicColors _colors(BuildContext context) =>
      Theme.of(context).extension<AtomicColors>() ??
      (MediaQuery.platformBrightnessOf(context) == Brightness.dark
          ? AtomicColors.dark
          : AtomicColors.light);

  @override
  Widget build(BuildContext context) {
    final c = _colors(context);
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    final toggle = _details
        ? StartupFailedPage.hideDetails
        : StartupFailedPage.showDetails;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: margin, vertical: AtomicSpace.x8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 2 * AtomicSpace.x8)
                    .clamp(0, double.infinity),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ExcludeSemantics(
                          child: Container(
                            key: const ValueKey('startup-failed-icon'),
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: c.danger,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(AtomicIcons.alertCircle,
                                size: 32, color: c.onDanger),
                          ),
                        ),
                      ),
                      const SizedBox(height: AtomicSpace.x5),
                      Semantics(
                        header: true,
                        child: Text(
                          StartupFailedPage.title,
                          textAlign: TextAlign.center,
                          style: AtomicType.headlineMedium
                              .copyWith(color: c.textPrimary),
                        ),
                      ),
                      const SizedBox(height: AtomicSpace.x2),
                      Text(
                        StartupFailedPage.body,
                        textAlign: TextAlign.center,
                        style: AtomicType.bodyMedium
                            .copyWith(color: c.textSecondary),
                      ),
                      const SizedBox(height: AtomicSpace.x6),
                      Center(
                        child: AtomicPressable(
                          key: const ValueKey('startup-failed-details'),
                          onTap: () => setState(() => _details = !_details),
                          semanticsLabel: toggle,
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AtomicSpace.x4,
                                vertical: AtomicSpace.x2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    toggle,
                                    style: AtomicType.labelLarge
                                        .copyWith(color: c.textPrimary),
                                  ),
                                ),
                                const SizedBox(width: AtomicSpace.x2),
                                Icon(
                                  _details
                                      ? AtomicIcons.chevronUp
                                      : AtomicIcons.chevronDown,
                                  size: 20,
                                  color: c.textPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_details) ...[
                        const SizedBox(height: AtomicSpace.x3),
                        DecoratedBox(
                          key: const ValueKey('startup-failed-trace'),
                          decoration: BoxDecoration(
                            color: c.surfaceInset,
                            borderRadius: AtomicRadius.mediumAll,
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.all(AtomicSpace.cardPadding),
                            child: Text(
                              widget.error,
                              style: AtomicType.mono
                                  .copyWith(color: c.textPrimary),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
