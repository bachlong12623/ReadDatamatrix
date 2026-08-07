import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_datamatrix/app_theme.dart';

void main() {
  test('AppColors lerp keeps accent', () {
    const a = AppColors(
      muted: Color(0xFF111111),
      accent: Color(0xFF2EE6A6),
      surface: Color(0xFF222222),
    );
    const b = AppColors(
      muted: Color(0xFF333333),
      accent: Color(0xFF00AA77),
      surface: Color(0xFF444444),
    );

    final mid = a.lerp(b, 0.5);
    expect(mid.accent, isNot(equals(a.accent)));
    expect(mid.accent.toARGB32(), isNot(0));
  });
}
