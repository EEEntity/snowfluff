// 应用主题颜色配置

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppTheme {
  static const _fontName = 'AppCJK';

  static Color _lighten(Color color, [double amount = 0.16]) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  static ColorScheme _buildScheme(Color seedColor, Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    final primary =
        brightness == Brightness.dark ? _lighten(seedColor, 0.10) : seedColor;
    final primaryContainer = brightness == Brightness.dark
        ? _lighten(seedColor, 0.22)
        : _lighten(seedColor, 0.28);

    final onPrimary = ThemeData.estimateBrightnessForColor(primary) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;
    final onPrimaryContainer =
        ThemeData.estimateBrightnessForColor(primaryContainer) ==
                Brightness.dark
            ? Colors.white
            : Colors.black;

    return base.copyWith(
      primary: primary,
      secondary: primary,
      tertiary: primary,
      primaryContainer: primaryContainer,
      onPrimary: onPrimary,
      onSecondary: onPrimary,
      onTertiary: onPrimary,
      onPrimaryContainer: onPrimaryContainer,
    );
  }

  static ThemeData light(Color seedColor) {
    final colorScheme = _buildScheme(seedColor, Brightness.light);

    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontName,
      brightness: Brightness.light,
      colorScheme: colorScheme,
    ).copyWith(
      switchTheme: _switchTheme(
        isDark: false,
        activeColor: colorScheme.primary,
      ),
      scaffoldBackgroundColor: Colors.white,
      listTileTheme: const ListTileThemeData(iconColor: Color(0xFF2C2C2C)),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontSize: 12),
        selectedIconTheme: IconThemeData(
          color: colorScheme.primary,
          size: 24.sp,
        ),
        unselectedIconTheme: IconThemeData(
          color: const Color(0xFF656565),
          size: 24.sp,
        ),
        unselectedItemColor: const Color(0xFF656565),
        selectedItemColor: colorScheme.primary,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 18.sp,
          fontWeight: FontWeight.w400,
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
    );
  }

  static ThemeData dark(Color seedColor) {
    final colorScheme = _buildScheme(seedColor, Brightness.dark);

    return ThemeData(
      useMaterial3: true,
      fontFamily: _fontName,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
    ).copyWith(
      switchTheme: _switchTheme(
        isDark: true,
        activeColor: colorScheme.primary,
      ),
      scaffoldBackgroundColor: const Color(0xFF2C2C2C),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontSize: 12),
        selectedIconTheme: IconThemeData(
          color: colorScheme.primary,
          size: 24.sp,
        ),
        unselectedIconTheme: IconThemeData(
          color: Colors.grey,
          size: 24.sp,
        ),
        unselectedItemColor: Colors.grey,
        selectedItemColor: colorScheme.primary,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: const Color(0xFF2C2C2C),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18.sp,
          fontWeight: FontWeight.w500,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
    );
  }

  static SwitchThemeData _switchTheme({
    required bool isDark,
    required Color activeColor,
  }) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          // 亮色模式：选中时白色圆点；深色模式：选中时黑色圆点
          return isDark ? Colors.black : Colors.white;
        }
        // 未选中和禁用态保持系统默认（灰色系）
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return activeColor.withValues(alpha: isDark ? 0.65 : 0.55);
        }
        return null;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return null;
      }),
    );
  }
}
