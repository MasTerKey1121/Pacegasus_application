import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central place for every color, gradient and text style used across the
/// app so all screens stay visually consistent with the Pacegasus mocks.
class AppColors {
  AppColors._();

  static const bg1 = Color(0xFF0A0816);
  static const bg2 = Color(0xFF150F2E);

  static const card = Color(0x0BFFFFFF); // white @ ~4.5%
  static const cardHi = Color(0x13FFFFFF); // white @ ~7.5%
  static const border = Color(0x17FFFFFF); // white @ ~9%
  static const borderHi = Color(0x29FFFFFF); // white @ ~16%

  static const textPrimary = Color(0xFFF4F2FF);
  static const textSecondary = Color(0xFF9D95BD);
  static const textTertiary = Color(0xFF6C6488);

  static const purple1 = Color(0xFF6D5EF7);
  static const purple2 = Color(0xFFA78BFA);

  static const gold1 = Color(0xFFF6B93B);
  static const gold2 = Color(0xFFFFD873);

  static const green1 = Color(0xFF0FB87F);
  static const green2 = Color(0xFF3FE0AB);

  static const red1 = Color(0xFFF2495C);
  static const red2 = Color(0xFFFF7A86);

  static const purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purple1, purple2],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gold1, gold2],
  );

  static const greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [green1, green2],
  );

  static const bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg2, bg1],
  );
}

class AppText {
  AppText._();

  static TextStyle heading({double size = 20, Color? color, FontWeight? weight}) =>
      GoogleFonts.kanit(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w600,
        color: color ?? AppColors.textPrimary,
      );

  static TextStyle body({double size = 14, Color? color, FontWeight? weight}) =>
      GoogleFonts.sarabun(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        height: 1.5,
      );
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg1,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.purple1,
      secondary: AppColors.gold1,
      surface: AppColors.bg2,
    ),
    textTheme: GoogleFonts.sarabunTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}

/// Reusable page background: dark gradient + a couple of soft glow blobs,
/// matching the radial highlights used in the web mocks.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -60,
            child: _glow(AppColors.purple1.withOpacity(.18), 220),
          ),
          Positioned(
            bottom: -100,
            right: -70,
            child: _glow(AppColors.gold1.withOpacity(.10), 260),
          ),
          child,
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
      ),
    );
  }
}
