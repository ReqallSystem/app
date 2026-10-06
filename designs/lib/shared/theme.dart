import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The reqall.net dashboard palette, shared with the omarchy plugin and the
/// desktop app: warm charcoal surfaces, a rose accent, cream text.
abstract final class Rq {
  static const bg = Color(0xFF2B1D1D);
  static const bgDeep = Color(0xFF1E1414);
  static const surface = Color(0xFF3A2A2A);
  static const surfaceHover = Color(0xFF4A3636);
  static const border = Color(0xFF5A4444);
  static const borderHover = Color(0xFF6E5555);
  static const text = Color(0xFFFDF5E6);
  static const textSoft = Color(0xFFDED5C8);
  static const muted = Color(0xFFA9A9A9);
  static const accent = Color(0xFFD4A5A5);
  static const accentHover = Color(0xFFE0BFBF);
  static const danger = Color(0xFFFF8A80);
  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFACC15);

  static TextStyle display({double size = 22, FontWeight weight = FontWeight.w700, Color color = text}) =>
      GoogleFonts.outfit(fontSize: size, fontWeight: weight, color: color, height: 1.15);

  static TextStyle body({double size = 14, FontWeight weight = FontWeight.w400, Color color = text}) =>
      GoogleFonts.dmSans(fontSize: size, fontWeight: weight, color: color, height: 1.45);

  static TextStyle mono({double size = 12, FontWeight weight = FontWeight.w500, Color color = text}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color, height: 1.35);

  static ThemeData theme() {
    // google_fonts 9 builds on package:material_ui, whose TextTheme is not
    // flutter/material's, so the theme takes the family name, not a TextTheme.
    return ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.dmSans().fontFamily,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: bg,
        primary: accent,
        onPrimary: bg,
      ),
      scaffoldBackgroundColor: bg,
      dividerColor: border,
    );
  }
}

/// Record kinds and their dashboard colours and glyphs.
enum Kind {
  issue(Color(0xFFFF6B6B), Icons.bug_report_outlined),
  spec(Color(0xFF51CF66), Icons.description_outlined),
  arch(Color(0xFFD4A5A5), Icons.account_tree_outlined),
  test(Color(0xFFFFD43B), Icons.science_outlined),
  todo(Color(0xFFC49A6C), Icons.check_box_outlined),
  info(Color(0xFF1098AD), Icons.lightbulb_outline),
  work(Color(0xFF868E96), Icons.construction_outlined);

  const Kind(this.color, this.icon);
  final Color color;
  final IconData icon;
}
