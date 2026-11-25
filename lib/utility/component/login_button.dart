import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The official Google-branded pill, with a native focus target and label.
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final platform = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    final theme = dark ? 'light' : 'dark';
    return AtomicPressable(
      onTap: isLoading ? null : signIn,
      semanticsLabel: text,
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey('login-google-face'),
        width: double.infinity,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              opacity: isLoading ? 0 : 1,
              duration: AtomicMotion.fade(context, AtomicMotion.quick),
              child: Image.asset(
                'assets/google-sign-in-$platform-$theme.png',
                key: const ValueKey('login-google-mark'),
                height: 48,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
            if (isLoading)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
          ],
        ),
      ),
    );
  }
}
