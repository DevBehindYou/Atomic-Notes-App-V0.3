import 'package:atomic_notes/utility/intropages/intro_art.dart';
import 'package:flutter/material.dart';

/// First-run tour, reached from the splash at `/onboardingscreen`.
///
/// Four pages, each leading with a drawn illustration that says what the
/// app does. The splash writes the `hasSeenOnboarding` flag before routing
/// here, so this screen persists nothing itself: Skip and Start both land on
/// the main page.
class OnBoardingScreen extends StatelessWidget {
  const OnBoardingScreen({super.key});

  static const List<(IntroArtKind, String, String, String)> _slides = [
    (
      IntroArtKind.grid,
      'Everything in one place',
      'Your notes,\nat a glance.',
      'Notes land in a grid you can scan in one look — newest first, '
          'with the date on every card.',
    ),
    (
      IntroArtKind.editor,
      'Write or tick off',
      'Plain notes\nand checklists.',
      'Write freely, or switch to a checklist when you need something '
          'you can tick off.',
    ),
    (
      IntroArtKind.sync,
      'Across your devices',
      'Sync that\nkeeps up.',
      'Sign in anywhere and your notes follow. Edits made on one device '
          'show up on the others.',
    ),
    (
      IntroArtKind.lock,
      'Yours alone',
      'Local first,\nlocked down.',
      'Your notes are saved on your device. With cloud sync on, Atomic '
          'Notes uses its server to sync them with your Google Drive. Add a '
          'fingerprint lock in Settings.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return IntroTour(
      doneLabel: 'Start',
      onFinish: () => Navigator.of(context).pushReplacementNamed('/mainpage'),
      pages: [
        for (final (kind, eyebrow, title, body) in _slides)
          IntroTourPage(
            art: (_) => IntroArt(kind),
            eyebrow: eyebrow,
            title: title,
            body: body,
          ),
      ],
    );
  }
}
