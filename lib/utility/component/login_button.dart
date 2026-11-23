import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// "Sign in with Google" (screens spec, Login), drawn to Google's sign-in
/// branding guidelines: the official four-colour mark, never recoloured; the
/// dark button style in the light theme and the light style in the dark
/// theme; a pill at least 48 high. Press, focus ring, keyboard activation and
/// the button role come from [AtomicPressable].
///
/// While [isLoading] the label fades out, a spinner fades in, the width stays,
/// and taps are ignored.
class LoginButton extends StatelessWidget {
  const LoginButton({
    super.key,
    required this.isLoading,
    required this.signIn,
    required this.text,
  });

  final VoidCallback signIn;
  final bool isLoading;
  final String text;

  /// Google's dark style, used on the light theme.
  static const GoogleButtonStyle onLight = GoogleButtonStyle(
    fill: Color(0xFF131314),
    stroke: Color(0xFF8E918F),
    label: Color(0xFFE3E3E3),
  );

  /// Google's light style, used on the dark theme.
  static const GoogleButtonStyle onDark = GoogleButtonStyle(
    fill: Color(0xFFFFFFFF),
    stroke: Color(0xFF747775),
    label: Color(0xFF1F1F1F),
  );

  static GoogleButtonStyle styleFor(Brightness brightness) =>
      brightness == Brightness.dark ? onDark : onLight;

  static const double height = 48;
  static const double markSize = 20;

  @override
  Widget build(BuildContext context) {
    final style = styleFor(Theme.of(context).brightness);
    final fade = AtomicMotion.fade(context, AtomicMotion.quick);
    final face = Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.string(
          googleMark,
          key: const ValueKey('login-google-mark'),
          width: markSize,
          height: markSize,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: AtomicSpace.x3),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AtomicType.labelLarge.copyWith(color: style.label),
          ),
        ),
      ],
    );
    return AtomicPressable(
      onTap: isLoading ? null : signIn,
      semanticsLabel: text,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          key: const ValueKey('login-google-face'),
          decoration: BoxDecoration(
            color: style.fill,
            borderRadius: AtomicRadius.pill,
            border: Border.all(color: style.stroke),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AtomicSpace.x4, vertical: AtomicSpace.x2),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                      opacity: isLoading ? 0 : 1, duration: fade, child: face),
                  if (isLoading)
                    SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: style.label),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of Google's two button styles.
@immutable
class GoogleButtonStyle {
  const GoogleButtonStyle({
    required this.fill,
    required this.stroke,
    required this.label,
  });

  final Color fill;
  final Color stroke;
  final Color label;
}

/// Google's standard "G" mark in its four brand colours.
const String googleMark = '<svg xmlns="http://www.w3.org/2000/svg" '
    'viewBox="0 0 48 48">'
    '<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85'
    'C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19'
    'C12.43 13.72 17.74 9.5 24 9.5z"/>'
    '<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02'
    'h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 '
    '7.09-17.65z"/>'
    '<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59'
    's.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 '
    '2.56 10.78l7.97-6.19z"/>'
    '<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6'
    'c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19'
    'C6.51 42.62 14.62 48 24 48z"/>'
    '</svg>';
