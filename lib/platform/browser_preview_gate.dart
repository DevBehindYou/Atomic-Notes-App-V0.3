import 'package:atomic_notes/theme/app_theme.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
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
    theme: AppTheme.light,
    home: Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoLabel('ATOMIC NOTES / WEB'),
                  SizedBox(height: AppSpace.sm),
                  HairRule(color: AppColors.ink),
                  SizedBox(height: AppSpace.lg),
                  EditorialHeading(
                    'WebApp in development',
                    style: AppType.headlineLg,
                  ),
                  SizedBox(height: AppSpace.sm),
                  Text(
                    'This preview cannot open, edit or sync notes. '
                    'Sign-in and local storage are not enabled. '
                    'Continue using the Android app for your existing notes.',
                    style: AppType.bodyMd,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
