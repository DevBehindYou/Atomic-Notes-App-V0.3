import 'package:atomic_notes/profile/profile_store.dart' show Avatars;
import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/motion/atomic_haptics.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/overlays/atomic_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The avatar picker (screens spec, Profile): a bottom sheet with a grid of
/// every bundled avatar. Tapping one sets it and closes the sheet.
///
/// Open it with [show]; the widget is the sheet's content.
class AvatarPickerDialog extends StatelessWidget {
  const AvatarPickerDialog({super.key});

  static const double tile = 64;

  /// Opens the picker as a bottom sheet over [context].
  static Future<void> show(BuildContext context) => showAtomicSheet<void>(
        context: context,
        builder: (_) => const AvatarPickerDialog(),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, profile) {
        final current = profile.avatarAsset;
        final cubit = context.read<ProfileCubit>();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Choose an avatar',
                  style: AtomicType.titleLarge.copyWith(color: c.textPrimary)),
            ),
            const SizedBox(height: AtomicSpace.x4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AtomicSpace.x3,
              runSpacing: AtomicSpace.x3,
              children: [
                for (var i = 0; i < Avatars.all.length; i++)
                  _AvatarTile(
                    key: ValueKey(Avatars.all[i]),
                    asset: Avatars.all[i],
                    number: i + 1,
                    selected: Avatars.all[i] == current,
                    onTap: () async {
                      await cubit.setAvatar(Avatars.all[i]);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
              ],
            ),
            const SizedBox(height: AtomicSpace.x5),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AtomicSpace.x2,
              runSpacing: AtomicSpace.x2,
              children: [
                if (profile.hasCustomAvatar)
                  AtomicButton.text(
                    label: 'Use default photo',
                    onPressed: () async {
                      await cubit.setAvatar(null);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                AtomicButton.text(
                  label: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One avatar: a circle, ringed in `accent` with a check when it is the
/// current one.
class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.asset,
    required this.number,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String asset;
  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const size = AvatarPickerDialog.tile;
    return AtomicPressable(
      semanticsLabel: 'Avatar $number',
      selected: selected,
      excludeSemantics: true,
      haptic: AtomicHaptic.selection,
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onTap,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: AtomicMotion.fade(context, AtomicMotion.quick),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: selected ? c.accent : c.surfaceInset,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      ColoredBox(color: c.surfaceInset),
                ),
              ),
            ),
            if (selected)
              Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface, width: 2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(AtomicIcons.check, size: 14, color: c.onAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
