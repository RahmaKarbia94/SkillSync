import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 16,
    this.opacity = 0.15,
    this.padding,
    this.margin,
    this.gradient,
    this.border,
    this.width,
    this.height,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;
  final Border? border;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: gradient ??
                  LinearGradient(
                    colors: [
                      Colors.white.withOpacity(opacity),
                      Colors.white.withOpacity(opacity * 0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
              border: border ??
                  Border.all(
                    color: Colors.white.withOpacity(0.25),
                    width: 1.2,
                  ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AppTheme {
  AppTheme._();

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B0F1A), Color(0xFF1A1F35), Color(0xFF0B0F1A)],
  );

  static ThemeData get themeData {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B0F1A),
      colorScheme: base.colorScheme.copyWith(
        primary: const Color(0xFF6C63FF),
        secondary: const Color(0xFF00D4FF),
        surface: const Color(0xFF141826),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
    );
  }
}