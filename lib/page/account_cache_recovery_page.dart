import 'package:atomic_notes/api/atomic_notes_api.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Shows no account identifiers or note contents. Signing out here preserves
/// the disk cache; SessionGuard performs the normal runtime teardown.
class AccountCacheRecoveryPage extends StatefulWidget {
  const AccountCacheRecoveryPage({super.key, this.signOut});
  final Future<void> Function()? signOut;

  @override
  State<AccountCacheRecoveryPage> createState() =>
      _AccountCacheRecoveryPageState();
}

class _AccountCacheRecoveryPageState extends State<AccountCacheRecoveryPage> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _switchAccount() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await (widget.signOut ?? ApiClient.instance.signOut)();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/loginpage', (_) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: AppColors.paper,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.screenMargin),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Finish syncing your previous account',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: AppSpace.lg),
                    const Text(
                        'This device still has unfinished changes or local-only notes from another '
                        'account. Those notes are preserved and hidden from this account. '
                        'Sign back into the previous account. Unlock the vault if needed, '
                        'use Upload all in Cloud Notes for local-only notes, and finish syncing before switching.'),
                    const SizedBox(height: AppSpace.md),
                    const Text('Do not uninstall the app or clear its storage. '
                        'If the vault is enabled, you may need your recovery phrase after signing in.'),
                    const SizedBox(height: AppSpace.lg),
                    if (_failed) ...[
                      const Text(
                          'Could not return to sign-in. Your stored notes are unchanged. Try again.',
                          style: TextStyle(color: AppColors.error)),
                      const SizedBox(height: AppSpace.md),
                    ],
                    FilledButton(
                      onPressed: _busy ? null : _switchAccount,
                      child: Text(_busy
                          ? 'Returning to sign-in…'
                          : 'Sign in to previous account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
