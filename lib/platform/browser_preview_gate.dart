import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_theme.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:flutter/material.dart';

/// Deliberately unavailable browser entry point, not a WebApp beta.
///
/// There is no build flag or route that enables native startup here. Browser
/// storage, auth, key handling and cross-tab ownership need separate proofs.
class BrowserPreviewGate extends StatelessWidget {
  const BrowserPreviewGate({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AtomicTheme.light,
    darkTheme: AtomicTheme.dark,
    home: Builder(
      builder: (context) {
        final c = context.colors;
        return Scaffold(
          backgroundColor: c.canvas,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AtomicSpace.x6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ATOMIC NOTES / WEB',
                        style: AtomicType.labelMedium.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AtomicSpace.x2),
                      HairRule(color: c.textPrimary),
                      const SizedBox(height: AtomicSpace.x6),
                      Text(
                        'WEBAPP IN DEVELOPMENT',
                        style: AtomicType.headlineLarge.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AtomicSpace.x2),
                      Text(
                        'This preview cannot open, edit or sync notes. '
                        'Sign-in and local storage are not enabled. '
                        'Continue using the Android app for your existing notes.',
                        style: AtomicType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
