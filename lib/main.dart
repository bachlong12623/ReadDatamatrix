import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'app_theme.dart';
import 'scanner_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // zxing-wasm hỗ trợ Data Matrix ổn định trên mọi trình duyệt hiện đại
    // (kể cả Firefox, nơi BarcodeDetector không có).
    MobileScannerPlatform.instance.setWebBarcodeReader(
      WebBarcodeReader.zxingWasm,
    );
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B1215),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const DataMatrixApp());
}

class DataMatrixApp extends StatelessWidget {
  const DataMatrixApp({super.key});

  static const _bg = Color(0xFF0B1215);
  static const _surface = Color(0xFF142028);
  static const _accent = Color(0xFF2EE6A6);
  static const _muted = Color(0xFF8FA3AD);

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      colorScheme: const ColorScheme.dark(
        surface: _surface,
        primary: _accent,
        onPrimary: Color(0xFF042018),
        secondary: Color(0xFF3D9EFF),
        onSurface: Color(0xFFE8F1F4),
        outline: Color(0xFF2A3A42),
      ),
    );

    return MaterialApp(
      title: 'DataMatrix Reader',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme).apply(
          bodyColor: const Color(0xFFE8F1F4),
          displayColor: const Color(0xFFE8F1F4),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.spaceGrotesk(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFE8F1F4),
            letterSpacing: -0.3,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: const Color(0xFF042018),
            textStyle: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE8F1F4),
            side: const BorderSide(color: Color(0xFF2A3A42)),
            textStyle: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _surface,
          contentTextStyle: GoogleFonts.spaceGrotesk(
            color: const Color(0xFFE8F1F4),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0B1215),
          labelStyle: const TextStyle(color: _muted),
          hintStyle: TextStyle(color: _muted.withValues(alpha: 0.7)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A3A42)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerColor: const Color(0xFF2A3A42),
        extensions: const [
          AppColors(muted: _muted, accent: _accent, surface: _surface),
        ],
      ),
      home: const ScannerPage(),
    );
  }
}
