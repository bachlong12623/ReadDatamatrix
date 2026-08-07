import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.muted,
    required this.accent,
    required this.surface,
  });

  final Color muted;
  final Color accent;
  final Color surface;

  @override
  AppColors copyWith({Color? muted, Color? accent, Color? surface}) {
    return AppColors(
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      surface: surface ?? this.surface,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
    );
  }
}
