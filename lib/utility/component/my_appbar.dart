// ignore_for_file: use_super_parameters

import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:flutter/material.dart';

/// Editorial page header: a squared Ink back-block on the left, the page name
/// set in Bebas Neue, and a hairline rule closing the header off from the
/// content — the "page in a technical journal" treatment.
class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String text;

  /// Runs instead of popping the route when the back block is tapped, for
  /// pages that must confirm before leaving (for example with
  /// `Navigator.maybePop`, which respects `PopScope`).
  final VoidCallback? onBack;

  const MyAppBar({
    required this.text,
    this.onBack,
    Key? key,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 66,
      centerTitle: false,
      titleSpacing: 0,
      leadingWidth: 56,
      leading: Center(
        child: GestureDetector(
          onTap: onBack ?? () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(left: AppSpace.md),
            height: 34,
            width: 34,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              borderRadius: AppRadius.std,
            ),
            child:
                const Icon(Icons.arrow_back, size: 17, color: AppColors.paper),
          ),
        ),
      ),
      title: EditorialHeading(text, style: AppType.headlineMd, maxLines: 1),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(AppStroke.rule),
        child: HairRule(color: AppColors.ink),
      ),
    );
  }
}
