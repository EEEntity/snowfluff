// 播放页背景

import 'dart:async';
import 'package:snowfluff/common/music_handler.dart';
import 'package:snowfluff/common/playback_state_cache_service.dart';
import 'package:snowfluff/pages/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlayBackground extends ConsumerWidget {
  final double? height;
  final BorderRadius? borderRadius;
  const PlayBackground({super.key, this.height, this.borderRadius});

  static Color _buildThemeFallbackColor({
    required Color themeSeed,
    required bool isDark,
  }) {
    final base = isDark ? Colors.black : Colors.white;
    final double mix = isDark ? 0.48 : 0.74;
    return (Color.lerp(themeSeed, base, mix) ?? base).withValues(alpha: 1.0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeSeed = ref.watch(themeColorProvider);
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final isDark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    final scaffoldBg = isDark ? Colors.black : Colors.white;
    final themeFallbackColor = _buildThemeFallbackColor(
      themeSeed: themeSeed,
      isDark: isDark,
    );

    // 仅监听最终计算出的背景色
    final asyncScheme = ref.watch(dynamicColorProvider);
    final cachedColor = ref.watch(dyColorProvider);
    final bool hasPersistedCache =
        SnowfluffMusicHandler().cachedBackgroundColorArgb != null ||
        PlaybackStateCacheService.bootstrapBackgroundColorArgb != null;

    // 优先使用当前计算出的颜色，loading时使用缓存
    final Color finalBgColor = asyncScheme.maybeWhen(
      data: (scheme) =>
          Color.lerp(scheme.primary, scaffoldBg, 0.2) ?? scaffoldBg,
      orElse: () => hasPersistedCache ? cachedColor : themeFallbackColor,
    );

    // 监听并自动更新缓存
    ref.listen<AsyncValue<ColorScheme>>(dynamicColorProvider, (prev, next) {
      if (next is AsyncData<ColorScheme>) {
        final scheme = next.value;
        final nextColor =
            Color.lerp(scheme.primary, scaffoldBg, 0.2) ?? scaffoldBg;
        if (nextColor.toARGB32() != ref.read(dyColorProvider).toARGB32()) {
          // 这里不需要postFrameCallback，listen是在build之外触发的
          ref.read(dyColorProvider.notifier).setColor(nextColor);
          unawaited(
            SnowfluffMusicHandler().updateBackgroundColorCache(nextColor),
          );
        }
      }
    });

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: finalBgColor.withValues(
              alpha: 1.0,
            ), // 减少Raster混合开销
          ),
          child: SizedBox.expand(), // 替代MediaQuery获取尺寸
        ),
      ),
    );
  }
}
