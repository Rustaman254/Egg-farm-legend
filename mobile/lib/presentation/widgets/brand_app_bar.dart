import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Mirrors the webapp's persistent brand-red header bar (see webapp/src/components/Layout.tsx)
/// -- every mobile screen uses this instead of a bare default AppBar so the app reads as the
/// same product as the webapp rather than generic Material chrome.
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final IconData? icon;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const BrandAppBar({super.key, required this.title, this.icon, this.actions, this.bottom});

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: Colors.white), const SizedBox(width: 8)],
          Text(
            title.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.6, color: Colors.white),
          ),
        ],
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}
