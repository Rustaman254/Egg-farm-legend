import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Mirrors the webapp's StatBar: label+value row over a thin bordered track, color shifting from
/// danger red through warn orange to "up" green as the value rises. The fill width animates on
/// every rebuild so hunger decay (polled) and feeding (instant) both read as motion, not a jump.
class StatBar extends StatelessWidget {
  final String label;
  final int value; // 0-100
  final IconData? icon;

  const StatBar({super.key, required this.label, required this.value, this.icon});

  Color _colorFor(int v) {
    if (v <= 20) return AppColors.danger;
    if (v <= 50) return AppColors.warn;
    return AppColors.secondary;
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(value);
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 6)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                  Text('$value%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
              const SizedBox(height: 3),
              Container(
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                  color: AppColors.surface2,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: value / 100),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, fraction, _) => LinearProgressIndicator(
                      value: fraction,
                      minHeight: 10,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
