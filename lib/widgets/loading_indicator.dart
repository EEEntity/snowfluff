// flutter原生加载动画

import 'package:snowfluff/common/settings_service.dart';
import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  final Size? size;
  const LoadingIndicator({super.key, this.size});

  Color _resolveIndicatorColor(BuildContext context) {
    try {
      final mode = SettingsService.themeMode;
      if (mode == ThemeMode.dark) return Colors.white30;
      if (mode == ThemeMode.light) return Colors.black38;
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark
          ? Colors.white30
          : Colors.black38;
    } catch (_) {
      return Theme.of(context).brightness == Brightness.dark
          ? Colors.white30
          : Colors.black38;
    }
  }

  @override
  Widget build(BuildContext context) {
    final indicatorColor = _resolveIndicatorColor(context);
    // 使用SizedBox应用size参数
    return SizedBox(
      width: size?.width ?? 56,
      height: size?.height ?? 56,
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2, // 线条粗细
          valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
        ),
      ),
    );
  }
}
