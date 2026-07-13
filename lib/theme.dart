import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Shadcn/Zinc Dark Palette ─────────────────────────────────────────────────
const kBg       = Color(0xFF09090B); // zinc-950
const kCard     = Color(0xFF18181B); // zinc-900
const kCard2    = Color(0xFF1C1C1F);
const kBorder   = Color(0xFF27272A); // zinc-800
const kBorder2  = Color(0xFF3F3F46); // zinc-700
const kInput    = Color(0xFF18181B);
const kText     = Color(0xFFFAFAFA); // zinc-50
const kText2    = Color(0xFFD4D4D8); // zinc-300
const kMuted    = Color(0xFFA1A1AA); // zinc-400
const kMuted2   = Color(0xFF71717A); // zinc-500
const kSubtle   = Color(0xFF52525B); // zinc-600
const kAccent   = Color(0xFF6366F1); // indigo-500
const kAccentFg = Color(0xFFFFFFFF);
const kAccentSub = Color(0xFF1E1B4B);
const kAccentMid = Color(0xFF818CF8); // indigo-400
const kGreen    = Color(0xFF22C55E);
const kGreenSub = Color(0xFF14532D);
const kRed      = Color(0xFFEF4444);
const kRedSub   = Color(0xFF450A0A);
const kYellow   = Color(0xFFF59E0B);
const kBlue     = Color(0xFF3B82F6);

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      surface: kBg,
      primary: kAccent,
      secondary: kAccentMid,
      error: kRed,
      onSurface: kText,
      outline: kBorder,
    ),
    textTheme: TextTheme(
      displayLarge:  _inter(32, FontWeight.w700, kText,  -1.0),
      displayMedium: _inter(24, FontWeight.w700, kText,  -0.6),
      titleLarge:    _inter(18, FontWeight.w600, kText,  -0.4),
      titleMedium:   _inter(15, FontWeight.w600, kText,  -0.2),
      titleSmall:    _inter(13, FontWeight.w600, kText,   0.0),
      bodyLarge:     _inter(14, FontWeight.w400, kText2,  0.0, 1.6),
      bodyMedium:    _inter(13, FontWeight.w400, kText2,  0.0, 1.5),
      bodySmall:     _inter(12, FontWeight.w400, kMuted,  0.0),
      labelLarge:    _inter(14, FontWeight.w500, kText,   0.0),
      labelMedium:   _inter(12, FontWeight.w500, kMuted,  0.0),
      labelSmall:    _inter(10, FontWeight.w500, kMuted2, 0.6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: kText,
      titleTextStyle: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      iconTheme: const IconThemeData(color: kMuted, size: 20),
    ),
    dividerTheme: const DividerThemeData(color: kBorder, thickness: 0.5),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kInput,
      hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kAccent, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kRed)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kCard,
      indicatorColor: kAccentSub,
      shadowColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((s) {
        final sel = s.contains(WidgetState.selected);
        return GoogleFonts.inter(
          color: sel ? kAccentMid : kMuted2,
          fontSize: 11, fontWeight: sel ? FontWeight.w600 : FontWeight.w400);
      }),
      iconTheme: WidgetStateProperty.resolveWith((s) {
        final sel = s.contains(WidgetState.selected);
        return IconThemeData(color: sel ? kAccentMid : kMuted2, size: 22);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kCard2,
      contentTextStyle: GoogleFonts.inter(color: kText, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: kBorder)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

TextStyle _inter(double size, FontWeight w, Color c, double ls, [double? h]) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, letterSpacing: ls, height: h);
