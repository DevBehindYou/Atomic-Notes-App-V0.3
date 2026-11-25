import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/mascot/mascot_stage.dart';
import 'package:atomic_notes/ui/motion/entrance.dart';
import 'package:atomic_notes/utility/component/atomic_brand.dart';
import 'package:flutter/material.dart';

/// The brief screen shown between sign-out and the login screen.
///
/// [SessionGuard] resets the whole navigation stack here on any sign-out.
/// Resetting straight to the login route from an auth-stream callback could
/// land while the navigator was still closing the logout confirmation dialog,
/// leaving a blank (black) navigator that only an app restart cleared. Landing
/// on this always-opaque screen first removes that race, and it gives the
/// sign-out a branded beat instead of a bare flash. Once its first frame is on
/// screen — so the navigator is idle again — it forwards to the login screen on
/// its own, so there is nothing for the user to restart.
///
/// Layout (screens spec, Logged out): the empty-state layout with the mascot
/// and a primary "Sign in" button, which goes now instead of after the beat.
/// Either way the screen navigates once.
class LoggedOutScreen extends StatefulWidget {
  const LoggedOutScreen({super.key});

  static const String title = 'You are signed out';
  static const String body = 'Taking you back to sign in.';
  static const String signInLabel = 'Sign in';

  @override
  State<LoggedOutScreen> createState() => _LoggedOutScreenState();
}

class _LoggedOutScreenState extends State<LoggedOutScreen> {
  bool _left = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toLogin());
  }

  Future<void> _toLogin() async {
    // A short branded beat, then hand off to login. The navigator is idle by
    // now (this screen has painted), so replacing the stack is safe here.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _leave();
  }

  /// The one navigation, from the beat or the button, whichever is first.
  void _leave() {
    if (!mounted || _left) return;
    _left = true;
    Navigator.pushNamedAndRemoveUntil(context, '/loginpage', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final margin = AtomicSpace.screenMargin(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: EntranceGroup(
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
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Entrance(
                          index: 0,
                          child: Center(
                            child: ExcludeSemantics(
                              child: MascotStage(
                                key: const ValueKey('loggedout-mascot'),
                                size: 96,
                                child: DevBehindYouMascot(
                                  size: MascotStage.artSize(96),
                                  secondary: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AtomicSpace.x5),
                        Entrance(
                          index: 1,
                          child: Semantics(
                            header: true,
                            child: Text(
                              LoggedOutScreen.title,
                              textAlign: TextAlign.center,
                              style: AtomicType.headlineMedium
                                  .copyWith(color: c.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: AtomicSpace.x2),
                        Entrance(
                          index: 2,
                          child: Text(
                            LoggedOutScreen.body,
                            textAlign: TextAlign.center,
                            style: AtomicType.bodyMedium
                                .copyWith(color: c.textSecondary),
                          ),
                        ),
                        const SizedBox(height: AtomicSpace.x6),
                        Entrance(
                          index: 3,
                          child: Center(
                            child: AtomicButton.primary(
                              key: const ValueKey('loggedout-sign-in'),
                              label: LoggedOutScreen.signInLabel,
                              onPressed: _leave,
                              size: AtomicButtonSize.large,
                            ),
                          ),
                        ),
                      ],
                    ),
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
