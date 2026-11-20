import 'package:atomic_notes/state/profile/profile_cubit.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The user's picture in a circle (components spec, Avatar): 40 dp in the
/// Home header, 88 dp on Profile. [frame] is a ring of `surfaceInset`
/// around the picture; 0 draws none.
///
/// Follows [ProfileCubit], so changing the avatar updates every place at once.
class ProfileAvatar extends StatelessWidget {
  final double size;
  final double frame;

  const ProfileAvatar({required this.size, this.frame = 3, super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BlocSelector<ProfileCubit, ProfileState, String>(
      selector: (state) => state.avatarAsset,
      builder: (context, avatarAsset) {
        return Container(
          height: size,
          width: size,
          padding: EdgeInsets.all(frame),
          decoration:
              BoxDecoration(color: c.surfaceInset, shape: BoxShape.circle),
          child: ClipOval(
            child: Image.asset(
              avatarAsset,
              fit: BoxFit.cover,
              // A missing file leaves the empty circle, not a red screen.
              errorBuilder: (_, __, ___) => ColoredBox(color: c.surfaceInset),
            ),
          ),
        );
      },
    );
  }
}
